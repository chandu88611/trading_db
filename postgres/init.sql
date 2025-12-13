-- CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- CREATE EXTENSION IF NOT EXISTS citext;

-- CREATE TABLE IF NOT EXISTS users (
--   id            BIGSERIAL PRIMARY KEY,
--   email         CITEXT NOT NULL UNIQUE,
--   name          TEXT,
--   password_hash TEXT NOT NULL,
--   is_email_verified BOOLEAN DEFAULT FALSE,
--   is_active     BOOLEAN DEFAULT TRUE,
--   is_admin      BOOLEAN DEFAULT FALSE,
--   verification_token TEXT,
--   reset_token   TEXT,
--   reset_token_expires_at TIMESTAMPTZ,
--   failed_login_attempts INT DEFAULT 0 NOT NULL,
--   locked_at     TIMESTAMPTZ,
--   mfa_enabled   BOOLEAN DEFAULT FALSE,
--   mfa_method    VARCHAR(20),
--   mfa_secret    TEXT,
--   recovery_codes JSONB,
--   created_at    TIMESTAMPTZ DEFAULT now(),
--   updated_at    TIMESTAMPTZ DEFAULT now(),
--   last_login_at TIMESTAMPTZ,
--   last_login_ip INET,
--   last_login_user_agent TEXT,
--   deleted_at    TIMESTAMPTZ
-- );

-- CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique_idx ON users(LOWER(email)) WHERE email IS NOT NULL;

-- CREATE TABLE IF NOT EXISTS auth_providers (
--   id BIGSERIAL PRIMARY KEY,
--   user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--   provider TEXT NOT NULL,
--   provider_user_id TEXT NOT NULL,
--   provider_meta JSONB,
--   created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
--   UNIQUE (provider, provider_user_id)
-- );

-- CREATE INDEX IF NOT EXISTS idx_auth_providers_user ON auth_providers(user_id);

-- CREATE TABLE IF NOT EXISTS broker_credentials (
--   id BIGSERIAL PRIMARY KEY,
--   user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--   key_name TEXT,
--   enc_api_key TEXT,
--   enc_api_secret TEXT,
--   enc_request_token TEXT,
--   status TEXT NOT NULL DEFAULT 'active',
--   created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
--   updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
--   UNIQUE(user_id, key_name)
-- );

-- CREATE INDEX IF NOT EXISTS idx_broker_credentials_user ON broker_credentials(user_id);

-- CREATE TABLE IF NOT EXISTS broker_sessions (
--   id BIGSERIAL PRIMARY KEY,
--   credential_id INT NOT NULL REFERENCES broker_credentials(id) ON DELETE CASCADE,
--   session_token TEXT,
--   expires_at TIMESTAMP WITH TIME ZONE,
--   last_refreshed_at TIMESTAMP WITH TIME ZONE,
--   status TEXT NOT NULL DEFAULT 'valid',
--   created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
-- );

-- CREATE INDEX IF NOT EXISTS idx_broker_sessions_credential ON broker_sessions(credential_id);
-- CREATE INDEX IF NOT EXISTS idx_broker_sessions_active ON broker_sessions(credential_id) WHERE (status = 'valid');


-- CREATE TABLE IF NOT EXISTS broker_jobs (
--   id BIGSERIAL PRIMARY KEY,
--   credential_id INT NOT NULL REFERENCES broker_credentials(id) ON DELETE CASCADE,
--   type TEXT NOT NULL,
--   payload JSONB,
--   attempts INT DEFAULT 0,
--   last_error TEXT,
--   status TEXT NOT NULL DEFAULT 'pending',
--     created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
--     updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
-- );

-- CREATE INDEX IF NOT EXISTS idx_broker_jobs_credential ON broker_jobs(credential_id);
-- CREATE INDEX IF NOT EXISTS idx_broker_jobs_status ON broker_jobs(status);

-- CREATE TABLE IF NOT EXISTS broker_events (
--   id BIGSERIAL PRIMARY KEY,
--   job_id INT NOT NULL REFERENCES broker_jobs(id) ON DELETE CASCADE,
--   event_type TEXT NOT NULL,
--   payload JSONB,
--   created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
-- );

-- CREATE INDEX IF NOT EXISTS idx_broker_events_job ON broker_events(job_id);

-- CREATE OR REPLACE FUNCTION trigger_set_timestamp()
-- RETURNS TRIGGER AS $$
-- BEGIN
--   NEW.updated_at = now();
--   RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- DROP TRIGGER IF EXISTS set_timestamp_broker_jobs ON broker_jobs;
-- CREATE TRIGGER set_timestamp_broker_jobs
-- BEFORE UPDATE ON broker_jobs
-- FOR EACH ROW
-- EXECUTE PROCEDURE trigger_set_timestamp();

-- CREATE TABLE IF NOT EXISTS user_refresh_tokens (
--   id BIGSERIAL PRIMARY KEY,
--   user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--   token_hash TEXT NOT NULL,
--   expires_at TIMESTAMP WITH TIME ZONE,
--   revoked BOOLEAN DEFAULT FALSE,
--   created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
-- );

-- CREATE INDEX IF NOT EXISTS idx_user_refresh_tokens_user ON user_refresh_tokens(user_id);

-- CREATE TABLE alert_snapshots (
--     id SERIAL PRIMARY KEY,
--     job_id INT NOT NULL REFERENCES broker_jobs(id) ON DELETE CASCADE,
--     ticker VARCHAR(20) NOT NULL,            
--     exchange VARCHAR(50),                   
--     interval VARCHAR(10),                   
--     bar_time TIMESTAMPTZ,                   
--     alert_time TIMESTAMPTZ,                 
--     open NUMERIC(15, 6),                    
--     close NUMERIC(15, 6),                   
--     high NUMERIC(15, 6),                    
--     low NUMERIC(15, 6),                     
--     volume NUMERIC(20, 2),                  
--     currency VARCHAR(10),                   
--     base_currency VARCHAR(10),               
--     created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
--     updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
-- );


-- CREATE TABLE trade_signals (
--     id SERIAL PRIMARY KEY,
--     job_id INT NOT NULL REFERENCES broker_jobs(id) ON DELETE CASCADE,
--     action VARCHAR(10) NOT NULL,        
--     symbol VARCHAR(20) NOT NULL,        
--     price NUMERIC(10, 5) NOT NULL,      
--     exchange VARCHAR(50) NOt NULL,               
--     signal_time TIMESTAMPTZ NOT NULL,    
--     created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
--     updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
-- );

-- CREATE TYPE billing_interval AS ENUM ('monthly', 'yearly');


-- CREATE TABLE IF NOT EXISTS subscription_plans (
--   id BIGSERIAL PRIMARY KEY,
--   plan_code TEXT NOT NULL UNIQUE,               
--   name TEXT NOT NULL,                          
--   description TEXT,
--   price_cents INT NOT NULL CHECK (price_cents >= 0),
--   currency VARCHAR(10) DEFAULT 'INR',
--   interval billing_interval NOT NULL DEFAULT 'monthly',
--   is_active BOOLEAN DEFAULT TRUE,
--   metadata JSONB,
--   created_at TIMESTAMPTZ DEFAULT now(),
--   updated_at TIMESTAMPTZ DEFAULT now()
-- );


-- CREATE TABLE IF NOT EXISTS user_subscriptions (
--   id BIGSERIAL PRIMARY KEY,
--   user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--   plan_id BIGINT NOT NULL REFERENCES subscription_plans(id),
  
--   status TEXT NOT NULL DEFAULT 'active'
--     CHECK (status IN ('active', 'past_due', 'canceled', 'expired')),
  
--   start_date TIMESTAMPTZ NOT NULL DEFAULT now(),
--   end_date TIMESTAMPTZ,
--   cancel_at TIMESTAMPTZ,                         
--   canceled_at TIMESTAMPTZ,                      
  
--   trial_start TIMESTAMPTZ,
--   trial_end TIMESTAMPTZ,
  
--   auto_renew BOOLEAN DEFAULT TRUE,
--   metadata JSONB,

--   created_at TIMESTAMPTZ DEFAULT now(),
--   updated_at TIMESTAMPTZ DEFAULT now()
-- );

-- CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user 
--   ON user_subscriptions(user_id);

-- CREATE INDEX IF NOT EXISTS idx_user_subscriptions_status 
--   ON user_subscriptions(status);

-- CREATE INDEX IF NOT EXISTS idx_user_subscriptions_active 
-- ON user_subscriptions(user_id)
-- WHERE status = 'active' AND end_date IS NULL;

-- CREATE INDEX IF NOT EXISTS idx_user_subscriptions_end_date 
-- ON user_subscriptions(end_date);


-- CREATE TABLE IF NOT EXISTS subscription_invoices (
--   id BIGSERIAL PRIMARY KEY,
--   subscription_id BIGINT NOT NULL REFERENCES user_subscriptions(id) ON DELETE CASCADE,
--   user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
--   plan_id BIGINT NOT NULL REFERENCES subscription_plans(id),

--   amount_cents INT NOT NULL,
--   currency VARCHAR(10) DEFAULT 'INR',

--   status TEXT NOT NULL DEFAULT 'pending'
--     CHECK (status IN ('pending', 'paid', 'failed', 'refunded')),

--   billing_period_start TIMESTAMPTZ NOT NULL,
--   billing_period_end   TIMESTAMPTZ NOT NULL,

--   payment_gateway TEXT,           
--   payment_reference TEXT,          

--   metadata JSONB,
--   created_at TIMESTAMPTZ DEFAULT now()
-- );

-- CREATE INDEX IF NOT EXISTS idx_invoices_subscription 
--   ON subscription_invoices(subscription_id);

-- CREATE INDEX IF NOT EXISTS idx_invoices_user 
--   ON subscription_invoices(user_id);

-- CREATE INDEX IF NOT EXISTS idx_invoices_status 
--   ON subscription_invoices(status);


-- CREATE TABLE IF NOT EXISTS subscription_payments (
--   id BIGSERIAL PRIMARY KEY,
--   invoice_id BIGINT REFERENCES subscription_invoices(id) ON DELETE SET NULL,
--   user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,

--   status TEXT NOT NULL CHECK (status IN ('initiated','successful','failed')),
--   amount_cents INT NOT NULL,
--   currency VARCHAR(10) DEFAULT 'INR',

--   gateway TEXT NOT NULL,                
--   gateway_event_id TEXT UNIQUE,         
--   gateway_payload JSONB,

--   created_at TIMESTAMPTZ DEFAULT now()
-- );


-- DROP TRIGGER IF EXISTS set_timestamp_subscription_plans ON subscription_plans;
-- CREATE TRIGGER set_timestamp_subscription_plans
-- BEFORE UPDATE ON subscription_plans
-- FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- DROP TRIGGER IF EXISTS set_timestamp_user_subscriptions ON user_subscriptions;
-- CREATE TRIGGER set_timestamp_user_subscriptions
-- BEFORE UPDATE ON user_subscriptions
-- FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();



-- ============================================================
-- COMPLETE SCHEMA + ENHANCEMENTS (PLANS + STRATEGIES)
-- Safe: does NOT drop existing tables, only adds/extends
-- ============================================================

-- ----------------------------
-- EXTENSIONS
-- ------------------------------ ============================================================
-- GLOBAL ALGO TRADING - COMPLETE SCHEMA (ENHANCED)
-- Safe to run multiple times (idempotent)
-- ============================================================

-- ----------------------------
-- EXTENSIONS
-- ----------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

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
  deleted_at    TIMESTAMPTZ
);

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
  open NUMERIC(15, 6),
  close NUMERIC(15, 6),
  high NUMERIC(15, 6),
  low NUMERIC(15, 6),
  volume NUMERIC(20, 2),
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
  price NUMERIC(10, 5) NOT NULL,
  exchange VARCHAR(50) NOT NULL,
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
