
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_type WHERE typname = 'trade_category'
  ) THEN
    CREATE TYPE trade_category AS ENUM (
      'FOREX',
      'CRYPTO',
      'INDEX',
      'STOCK',
      'COMMODITY',
      'FUTURES',
      'UNKNOWN'
    );
  END IF;
END$$;

-- ----------------------------
-- COMMON UPDATED_AT TRIGGER
-- ----------------------------
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- USERS
-- ============================================================
CREATE TABLE IF NOT EXISTS users (
  id            BIGSERIAL PRIMARY KEY,
  email         CITEXT NOT NULL UNIQUE,
  name          TEXT,
  password_hash TEXT NOT NULL,
  is_email_verified BOOLEAN DEFAULT FALSE,
  is_active     BOOLEAN DEFAULT TRUE,
  is_admin      BOOLEAN DEFAULT FALSE,
  verification_token TEXT,
  reset_token   TEXT,
  reset_token_expires_at TIMESTAMPTZ,
  failed_login_attempts INT DEFAULT 0 NOT NULL,
  locked_at     TIMESTAMPTZ,
  mfa_enabled   BOOLEAN DEFAULT FALSE,
  mfa_method    VARCHAR(20),
  mfa_secret    TEXT,
  recovery_codes JSONB,
  created_at    TIMESTAMPTZ DEFAULT now(),
  updated_at    TIMESTAMPTZ DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  last_login_ip INET,
  last_login_user_agent TEXT,
  deleted_at    TIMESTAMPTZ,
  allow_trade BOOLEAN DEFAULT TRUE,
  allow_copy_trade BOOLEAN DEFAULT TRUE
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS allow_trade BOOLEAN DEFAULT TRUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS allow_copy_trade BOOLEAN DEFAULT TRUE;

CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique_idx
ON users(LOWER(email)) WHERE email IS NOT NULL;

-- ============================================================
-- AUTH PROVIDERS
-- ============================================================
CREATE TABLE IF NOT EXISTS auth_providers (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  provider_user_id TEXT NOT NULL,
  provider_meta JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE (provider, provider_user_id)
);

CREATE INDEX IF NOT EXISTS idx_auth_providers_user ON auth_providers(user_id);

-- ============================================================
-- BROKER CREDENTIALS / SESSIONS / JOBS / EVENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS broker_credentials (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key_name TEXT,
  enc_api_key TEXT,
  enc_api_secret TEXT,
  enc_request_token TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, key_name)
);

CREATE INDEX IF NOT EXISTS idx_broker_credentials_user
ON broker_credentials(user_id);

DROP TRIGGER IF EXISTS set_timestamp_broker_credentials ON broker_credentials;
CREATE TRIGGER set_timestamp_broker_credentials
BEFORE UPDATE ON broker_credentials
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS broker_sessions (
  id BIGSERIAL PRIMARY KEY,
  credential_id BIGINT NOT NULL REFERENCES broker_credentials(id) ON DELETE CASCADE,
  session_token TEXT,
  expires_at TIMESTAMPTZ,
  last_refreshed_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'valid',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_broker_sessions_credential
ON broker_sessions(credential_id);

CREATE INDEX IF NOT EXISTS idx_broker_sessions_active
ON broker_sessions(credential_id) WHERE (status = 'valid');

CREATE TABLE IF NOT EXISTS broker_jobs (
  id BIGSERIAL PRIMARY KEY,
  credential_id BIGINT NOT NULL REFERENCES broker_credentials(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  payload JSONB,
  attempts INT DEFAULT 0,
  last_error TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_broker_jobs_credential
ON broker_jobs(credential_id);

CREATE INDEX IF NOT EXISTS idx_broker_jobs_status
ON broker_jobs(status);

CREATE TABLE IF NOT EXISTS broker_events (
  id BIGSERIAL PRIMARY KEY,
  job_id BIGINT NOT NULL REFERENCES broker_jobs(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  payload JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_broker_events_job
ON broker_events(job_id);

DROP TRIGGER IF EXISTS set_timestamp_broker_jobs ON broker_jobs;
CREATE TRIGGER set_timestamp_broker_jobs
BEFORE UPDATE ON broker_jobs
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- USER REFRESH TOKENS
-- ============================================================
CREATE TABLE IF NOT EXISTS user_refresh_tokens (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ,
  revoked BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_refresh_tokens_user
ON user_refresh_tokens(user_id);

-- ============================================================
-- ALERT SNAPSHOTS
-- ============================================================
CREATE TABLE IF NOT EXISTS alert_snapshots (
  id SERIAL PRIMARY KEY,
  job_id BIGINT NOT NULL REFERENCES broker_jobs(id) ON DELETE CASCADE,
  ticker VARCHAR(20) NOT NULL,
  exchange VARCHAR(50),
  interval VARCHAR(10),
  bar_time TIMESTAMPTZ,
  alert_time TIMESTAMPTZ,
  open NUMERIC(30, 8),
  close NUMERIC(30, 8),
  high NUMERIC(30, 8),
  low NUMERIC(30, 8),
  volume NUMERIC(30, 2),
  currency VARCHAR(10),
  base_currency VARCHAR(10),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS set_timestamp_alert_snapshots ON alert_snapshots;
CREATE TRIGGER set_timestamp_alert_snapshots
BEFORE UPDATE ON alert_snapshots
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- TRADE SIGNALS
-- ============================================================
CREATE TABLE IF NOT EXISTS trade_signals (
  id SERIAL PRIMARY KEY,
  job_id BIGINT NOT NULL REFERENCES broker_jobs(id) ON DELETE CASCADE,
  action VARCHAR(10) NOT NULL,
  symbol VARCHAR(20) NOT NULL,
  price NUMERIC(30, 8) NOT NULL,
  exchange VARCHAR(50) NOT NULL,
  asset_type trade_category NOT NULL,
  signal_time TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS set_timestamp_trade_signals ON trade_signals;
CREATE TRIGGER set_timestamp_trade_signals
BEFORE UPDATE ON trade_signals
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- ENUMS (SAFE CREATE / SAFE ALTER)
-- ============================================================

DO $$ BEGIN
  CREATE TYPE market_category AS ENUM ('FOREX', 'CRYPTO', 'INDIA');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE execution_flow AS ENUM ('PINE_CONNECTOR', 'MANAGED', 'API');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- billing_interval might already exist from old schema:
DO $$ BEGIN
  CREATE TYPE billing_interval AS ENUM ('monthly', 'yearly');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ensure 'lifetime' exists
DO $$ BEGIN
  BEGIN
    ALTER TYPE billing_interval ADD VALUE IF NOT EXISTS 'lifetime';
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

DO $$ BEGIN
  CREATE TYPE subscription_status AS ENUM (
    'trialing',
    'active',
    'past_due',
    'liquidate_only',
    'paused',
    'canceled',
    'expired'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE user_strategy_status AS ENUM ('active', 'paused', 'stopped');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE trading_account_status AS ENUM ('pending', 'verified', 'blocked');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- SUBSCRIPTION PLANS (ENHANCED)
-- ============================================================

CREATE TABLE IF NOT EXISTS subscription_plans (
  id BIGSERIAL PRIMARY KEY,
  plan_code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  description TEXT,
  price_cents INT NOT NULL CHECK (price_cents >= 0),
  currency VARCHAR(10) DEFAULT 'INR',
  interval billing_interval NOT NULL DEFAULT 'monthly',
  is_active BOOLEAN DEFAULT TRUE,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- new plan design columns (safe)
ALTER TABLE subscription_plans
  ADD COLUMN IF NOT EXISTS category market_category,
  ADD COLUMN IF NOT EXISTS execution_flow execution_flow,
  ADD COLUMN IF NOT EXISTS max_active_strategies INT,
  ADD COLUMN IF NOT EXISTS max_connected_accounts INT,
  ADD COLUMN IF NOT EXISTS max_daily_trades INT,
  ADD COLUMN IF NOT EXISTS max_lot_per_trade NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS feature_flags JSONB;

-- defaults (safe)
UPDATE subscription_plans
SET
  category = COALESCE(category, 'CRYPTO'::market_category),
  execution_flow = COALESCE(execution_flow, 'API'::execution_flow),
  max_active_strategies = COALESCE(max_active_strategies, 1),
  max_connected_accounts = COALESCE(max_connected_accounts, 1),
  feature_flags = COALESCE(feature_flags, '{}'::jsonb);

-- enforce required fields after backfill
ALTER TABLE subscription_plans
  ALTER COLUMN category SET NOT NULL,
  ALTER COLUMN execution_flow SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_subscription_plans_category ON subscription_plans(category);
CREATE INDEX IF NOT EXISTS idx_subscription_plans_execution_flow ON subscription_plans(execution_flow);
CREATE INDEX IF NOT EXISTS idx_subscription_plans_active ON subscription_plans(is_active);

DROP TRIGGER IF EXISTS set_timestamp_subscription_plans ON subscription_plans;
CREATE TRIGGER set_timestamp_subscription_plans
BEFORE UPDATE ON subscription_plans
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- USER SUBSCRIPTIONS (ENHANCED + COMPATIBLE)
-- ============================================================

CREATE TABLE IF NOT EXISTS user_subscriptions (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id),

  -- legacy status (kept for compatibility)
  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'past_due', 'canceled', 'expired')),

  start_date TIMESTAMPTZ NOT NULL DEFAULT now(),
  end_date TIMESTAMPTZ,
  cancel_at TIMESTAMPTZ,
  canceled_at TIMESTAMPTZ,

  trial_start TIMESTAMPTZ,
  trial_end TIMESTAMPTZ,

  auto_renew BOOLEAN DEFAULT TRUE,
  metadata JSONB,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- new subscription-state model columns (safe)
ALTER TABLE user_subscriptions
  ADD COLUMN IF NOT EXISTS status_v2 subscription_status,
  ADD COLUMN IF NOT EXISTS webhook_token TEXT,
  ADD COLUMN IF NOT EXISTS execution_enabled BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS liquidate_only_until TIMESTAMPTZ;

-- backfill status_v2 from legacy status
UPDATE user_subscriptions
SET status_v2 =
  CASE status
    WHEN 'active' THEN 'active'::subscription_status
    WHEN 'past_due' THEN 'past_due'::subscription_status
    WHEN 'canceled' THEN 'canceled'::subscription_status
    WHEN 'expired' THEN 'expired'::subscription_status
    ELSE 'active'::subscription_status
  END
WHERE status_v2 IS NULL;

-- generate webhook token (important for PineConnector)
UPDATE user_subscriptions
SET webhook_token = encode(gen_random_bytes(24), 'hex')
WHERE webhook_token IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_subscriptions_webhook_token
ON user_subscriptions(webhook_token) WHERE webhook_token IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user ON user_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_status ON user_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_status_v2 ON user_subscriptions(status_v2);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_end_date ON user_subscriptions(end_date);

DROP TRIGGER IF EXISTS set_timestamp_user_subscriptions ON user_subscriptions;
CREATE TRIGGER set_timestamp_user_subscriptions
BEFORE UPDATE ON user_subscriptions
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- SUBSCRIPTION INVOICES
-- ============================================================

CREATE TABLE IF NOT EXISTS subscription_invoices (
  id BIGSERIAL PRIMARY KEY,
  subscription_id BIGINT NOT NULL REFERENCES user_subscriptions(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id),

  amount_cents INT NOT NULL,
  currency VARCHAR(10) DEFAULT 'INR',

  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),

  billing_period_start TIMESTAMPTZ NOT NULL,
  billing_period_end   TIMESTAMPTZ NOT NULL,

  payment_gateway TEXT,
  payment_reference TEXT,

  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoices_subscription ON subscription_invoices(subscription_id);
CREATE INDEX IF NOT EXISTS idx_invoices_user ON subscription_invoices(user_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON subscription_invoices(status);

-- ============================================================
-- SUBSCRIPTION PAYMENTS
-- ============================================================

CREATE TABLE IF NOT EXISTS subscription_payments (
  id BIGSERIAL PRIMARY KEY,
  invoice_id BIGINT REFERENCES subscription_invoices(id) ON DELETE SET NULL,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  status TEXT NOT NULL CHECK (status IN ('initiated','successful','failed')),
  amount_cents INT NOT NULL,
  currency VARCHAR(10) DEFAULT 'INR',

  gateway TEXT NOT NULL,
  gateway_event_id TEXT UNIQUE,
  gateway_payload JSONB,

  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- STRATEGIES (NEW)
-- ============================================================

CREATE TABLE IF NOT EXISTS strategies (
  id BIGSERIAL PRIMARY KEY,

  strategy_code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  description TEXT,

  category market_category NOT NULL,

  -- strategy can support multiple flows
  supported_execution_flows execution_flow[] NOT NULL,

  version INT NOT NULL DEFAULT 1,
  default_params JSONB NOT NULL DEFAULT '{}'::jsonb,

  risk_profile TEXT,
  capital_requirement NUMERIC(12,2),

  is_active BOOLEAN DEFAULT TRUE,
  is_deprecated BOOLEAN DEFAULT FALSE,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_strategies_category ON strategies(category);
CREATE INDEX IF NOT EXISTS idx_strategies_active ON strategies(is_active);
CREATE INDEX IF NOT EXISTS idx_strategies_deprecated ON strategies(is_deprecated);

DROP TRIGGER IF EXISTS set_timestamp_strategies ON strategies;
CREATE TRIGGER set_timestamp_strategies
BEFORE UPDATE ON strategies
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- PLAN ↔ STRATEGY (NEW)
-- ============================================================

CREATE TABLE IF NOT EXISTS plan_strategies (
  id BIGSERIAL PRIMARY KEY,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  strategy_id BIGINT NOT NULL REFERENCES strategies(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(plan_id, strategy_id)
);

CREATE INDEX IF NOT EXISTS idx_plan_strategies_plan ON plan_strategies(plan_id);
CREATE INDEX IF NOT EXISTS idx_plan_strategies_strategy ON plan_strategies(strategy_id);

-- ============================================================
-- USER TRADING ACCOUNTS (NEW)
-- supports API (crypto/india) + managed/forex + pine connector
-- ============================================================

CREATE TABLE IF NOT EXISTS user_trading_accounts (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  broker TEXT NOT NULL,
  execution_flow execution_flow NOT NULL,

  account_label TEXT,
  account_meta JSONB DEFAULT '{}'::jsonb,

  -- encrypted blob (you control encryption in backend)
  credentials_encrypted TEXT NOT NULL,

  status trading_account_status NOT NULL DEFAULT 'pending',
  last_verified_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_trading_accounts_user ON user_trading_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_user_trading_accounts_flow ON user_trading_accounts(execution_flow);
CREATE INDEX IF NOT EXISTS idx_user_trading_accounts_status ON user_trading_accounts(status);

DROP TRIGGER IF EXISTS set_timestamp_user_trading_accounts ON user_trading_accounts;
CREATE TRIGGER set_timestamp_user_trading_accounts
BEFORE UPDATE ON user_trading_accounts
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- USER STRATEGY INSTANCES (NEW)
-- freezes params/version at activation time
-- tracks per (user, account, strategy)
-- ============================================================

CREATE TABLE IF NOT EXISTS user_strategy_instances (
  id BIGSERIAL PRIMARY KEY,

  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subscription_id BIGINT NOT NULL REFERENCES user_subscriptions(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id),
  strategy_id BIGINT NOT NULL REFERENCES strategies(id),
  trading_account_id BIGINT REFERENCES user_trading_accounts(id) ON DELETE SET NULL,

  status user_strategy_status NOT NULL DEFAULT 'active',

  strategy_version INT NOT NULL,
  frozen_params JSONB NOT NULL DEFAULT '{}'::jsonb,

  activated_at TIMESTAMPTZ DEFAULT now(),
  paused_at TIMESTAMPTZ,
  stopped_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ensure user cannot activate same strategy twice for same account
CREATE UNIQUE INDEX IF NOT EXISTS uq_user_strategy_per_account
ON user_strategy_instances(user_id, strategy_id, trading_account_id);

CREATE INDEX IF NOT EXISTS idx_user_strategy_instances_user ON user_strategy_instances(user_id);
CREATE INDEX IF NOT EXISTS idx_user_strategy_instances_subscription ON user_strategy_instances(subscription_id);
CREATE INDEX IF NOT EXISTS idx_user_strategy_instances_plan ON user_strategy_instances(plan_id);
CREATE INDEX IF NOT EXISTS idx_user_strategy_instances_strategy ON user_strategy_instances(strategy_id);
CREATE INDEX IF NOT EXISTS idx_user_strategy_instances_account ON user_strategy_instances(trading_account_id);
CREATE INDEX IF NOT EXISTS idx_user_strategy_instances_status ON user_strategy_instances(status);

DROP TRIGGER IF EXISTS set_timestamp_user_strategy_instances ON user_strategy_instances;
CREATE TRIGGER set_timestamp_user_strategy_instances
BEFORE UPDATE ON user_strategy_instances
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- PINE CONNECTOR HEARTBEATS (NEW)
-- EA/VPS should ping every 1-5 mins
-- ============================================================

CREATE TABLE IF NOT EXISTS pine_connector_heartbeats (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subscription_id BIGINT NOT NULL REFERENCES user_subscriptions(id) ON DELETE CASCADE,
  trading_account_id BIGINT REFERENCES user_trading_accounts(id) ON DELETE SET NULL,

  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ip INET,
  user_agent TEXT,
  meta JSONB DEFAULT '{}'::jsonb,

  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_pine_heartbeat_user_sub
ON pine_connector_heartbeats(user_id, subscription_id);

CREATE INDEX IF NOT EXISTS idx_pine_heartbeat_last_seen
ON pine_connector_heartbeats(last_seen_at);

-- ============================================================
-- END
-- ============================================================


CREATE TABLE IF NOT EXISTS user_billing_details (
  id              BIGSERIAL PRIMARY KEY,
  user_id         BIGINT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

  -- PAN / Personal
  pan_number      VARCHAR(10),

  -- Bank
  account_holder_name VARCHAR(120),
  account_number  VARCHAR(34),
  ifsc_code        VARCHAR(11),
  bank_name        VARCHAR(120),
  branch           VARCHAR(120),

  -- Address (for GST & invoices)
  address_line1   VARCHAR(255),
  address_line2   VARCHAR(255),
  city            VARCHAR(80),
  state           VARCHAR(80),
  pincode         VARCHAR(10),

  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Basic validations (optional but good)
  CONSTRAINT pan_format_chk CHECK (pan_number IS NULL OR pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]{1}$'),
  CONSTRAINT ifsc_format_chk CHECK (ifsc_code IS NULL OR ifsc_code ~ '^[A-Z]{4}0[A-Z0-9]{6}$')
);

-- auto update updated_at
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_user_billing_updated_at ON user_billing_details;
CREATE TRIGGER trg_user_billing_updated_at
BEFORE UPDATE ON user_billing_details
FOR EACH ROW EXECUTE FUNCTION set_updated_at();



-- ---------------------------
-- 1) ENUMS (types / use-cases)
-- ---------------------------

DO $$ BEGIN
  CREATE TYPE contact_type AS ENUM (
    'support',
    'sales',
    'billing',
    'legal',
    'whatsapp',
    'general',
    'other'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE address_type AS ENUM (
    'registered',
    'corporate',
    'billing',
    'branch',
    'warehouse',
    'other'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------
-- 2) MAIN SETTINGS TABLE
-- ---------------------------

-- If you have organizations table, keep organization_id.
-- Otherwise, remove organization_id + UNIQUE and just keep one row.

CREATE TABLE IF NOT EXISTS admin_settings (
  id              BIGSERIAL PRIMARY KEY,

  organization_id BIGINT UNIQUE, -- one settings row per org

  title           VARCHAR(150) NOT NULL DEFAULT '',
  description     TEXT NOT NULL DEFAULT '',
  logo_url        TEXT,

  -- Editor HTML content
  privacy_policy        TEXT NOT NULL DEFAULT '',
  refund_policy         TEXT NOT NULL DEFAULT '',
  agreement             TEXT NOT NULL DEFAULT '',
  terms_and_conditions  TEXT NOT NULL DEFAULT '',

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()

  -- If org table exists, enable FK:
  -- ,CONSTRAINT fk_admin_settings_org
  --   FOREIGN KEY (organization_id)
  --   REFERENCES organizations(id)
  --   ON DELETE CASCADE
);

-- updated_at trigger
DO $$ BEGIN
  CREATE OR REPLACE FUNCTION set_updated_at_admin_settings()
  RETURNS TRIGGER AS $fn$
  BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
  END;
  $fn$ LANGUAGE plpgsql;
EXCEPTION
  WHEN duplicate_function THEN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_admin_settings_updated_at ON admin_settings;

CREATE TRIGGER trg_admin_settings_updated_at
BEFORE UPDATE ON admin_settings
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_admin_settings();


-- ---------------------------
-- 3) EMAILS (multiple with type)
-- ---------------------------

CREATE TABLE IF NOT EXISTS admin_setting_emails (
  id           BIGSERIAL PRIMARY KEY,
  settings_id  BIGINT NOT NULL,

  type         contact_type NOT NULL DEFAULT 'support',
  email        VARCHAR(320) NOT NULL,
  label        VARCHAR(120),
  is_primary   BOOLEAN NOT NULL DEFAULT FALSE,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT fk_setting_emails_settings
    FOREIGN KEY (settings_id)
    REFERENCES admin_settings(id)
    ON DELETE CASCADE
);

-- One primary email per settings row
CREATE UNIQUE INDEX IF NOT EXISTS uq_setting_primary_email
ON admin_setting_emails(settings_id)
WHERE is_primary = TRUE;

-- avoid duplicates (same email + type)
CREATE UNIQUE INDEX IF NOT EXISTS uq_setting_email_unique
ON admin_setting_emails(settings_id, type, lower(email));

-- updated_at trigger for emails
DO $$ BEGIN
  CREATE OR REPLACE FUNCTION set_updated_at_setting_emails()
  RETURNS TRIGGER AS $fn$
  BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
  END;
  $fn$ LANGUAGE plpgsql;
EXCEPTION
  WHEN duplicate_function THEN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_setting_emails_updated_at ON admin_setting_emails;

CREATE TRIGGER trg_setting_emails_updated_at
BEFORE UPDATE ON admin_setting_emails
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_setting_emails();


-- ---------------------------
-- 4) PHONES (multiple with type)
-- ---------------------------

CREATE TABLE IF NOT EXISTS admin_setting_phones (
  id           BIGSERIAL PRIMARY KEY,
  settings_id  BIGINT NOT NULL,

  type         contact_type NOT NULL DEFAULT 'support',
  country_code VARCHAR(8) NOT NULL DEFAULT '+91',
  number       VARCHAR(32) NOT NULL,
  label        VARCHAR(120),
  is_primary   BOOLEAN NOT NULL DEFAULT FALSE,
  is_whatsapp  BOOLEAN NOT NULL DEFAULT FALSE,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT fk_setting_phones_settings
    FOREIGN KEY (settings_id)
    REFERENCES admin_settings(id)
    ON DELETE CASCADE
);

-- One primary phone per settings row
CREATE UNIQUE INDEX IF NOT EXISTS uq_setting_primary_phone
ON admin_setting_phones(settings_id)
WHERE is_primary = TRUE;

-- avoid duplicates (same phone + type)
CREATE UNIQUE INDEX IF NOT EXISTS uq_setting_phone_unique
ON admin_setting_phones(settings_id, type, country_code, number);

-- updated_at trigger for phones
DO $$ BEGIN
  CREATE OR REPLACE FUNCTION set_updated_at_setting_phones()
  RETURNS TRIGGER AS $fn$
  BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
  END;
  $fn$ LANGUAGE plpgsql;
EXCEPTION
  WHEN duplicate_function THEN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_setting_phones_updated_at ON admin_setting_phones;

CREATE TRIGGER trg_setting_phones_updated_at
BEFORE UPDATE ON admin_setting_phones
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_setting_phones();


-- ---------------------------
-- 5) ADDRESSES (multiple with type)
-- ---------------------------

CREATE TABLE IF NOT EXISTS admin_setting_addresses (
  id           BIGSERIAL PRIMARY KEY,
  settings_id  BIGINT NOT NULL,

  type         address_type NOT NULL DEFAULT 'registered',
  label        VARCHAR(120),

  line1        VARCHAR(255) NOT NULL,
  line2        VARCHAR(255),
  city         VARCHAR(120) NOT NULL,
  state        VARCHAR(120) NOT NULL,
  pincode      VARCHAR(20)  NOT NULL,
  country      VARCHAR(120) NOT NULL DEFAULT 'India',

  google_map_url TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT fk_setting_addresses_settings
    FOREIGN KEY (settings_id)
    REFERENCES admin_settings(id)
    ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_setting_addresses_settings_id
ON admin_setting_addresses(settings_id);

-- updated_at trigger for addresses
DO $$ BEGIN
  CREATE OR REPLACE FUNCTION set_updated_at_setting_addresses()
  RETURNS TRIGGER AS $fn$
  BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
  END;
  $fn$ LANGUAGE plpgsql;
EXCEPTION
  WHEN duplicate_function THEN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_setting_addresses_updated_at ON admin_setting_addresses;

CREATE TRIGGER trg_setting_addresses_updated_at
BEFORE UPDATE ON admin_setting_addresses
FOR EACH ROW
EXECUTE FUNCTION set_updated_at_setting_addresses();



CREATE TABLE IF NOT EXISTS razorpay_orders (
  id BIGSERIAL PRIMARY KEY,

  invoice_id BIGINT NOT NULL REFERENCES subscription_invoices(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  razorpay_order_id TEXT NOT NULL UNIQUE,
  receipt TEXT, 
  amount_cents INT NOT NULL,
  currency VARCHAR(10) NOT NULL DEFAULT 'INR',
  status TEXT NOT NULL DEFAULT 'created'
    CHECK (status IN ('created','attempted','paid','failed','cancelled')),

  notes JSONB DEFAULT '{}'::jsonb,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_razorpay_orders_invoice ON razorpay_orders(invoice_id);
CREATE INDEX IF NOT EXISTS idx_razorpay_orders_user ON razorpay_orders(user_id);

DROP TRIGGER IF EXISTS set_timestamp_razorpay_orders ON razorpay_orders;
CREATE TRIGGER set_timestamp_razorpay_orders
BEFORE UPDATE ON razorpay_orders
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();
