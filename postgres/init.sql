CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'trade_category') THEN
    CREATE TYPE trade_category AS ENUM (
      'FOREX','CRYPTO','INDEX','STOCK','COMMODITY','FUTURES','UNKNOWN'
    );
  END IF;
END$$;

DO $$ BEGIN
  CREATE TYPE billing_interval AS ENUM ('monthly', 'yearly', 'lifetime');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE subscription_status AS ENUM (
    'trialing','active','past_due','liquidate_only','paused','canceled','expired'
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

DO $$ BEGIN
  CREATE TYPE execution_flow AS ENUM ('PINE_CONNECTOR', 'MANAGED', 'API', 'direct');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE market_category AS ENUM ('FOREX', 'CRYPTO', 'INDIAN');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- copy trading enums
DO $$ BEGIN
  CREATE TYPE copy_master_source_type AS ENUM ('TRADING_ACCOUNT', 'STRATEGY');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE copy_master_visibility AS ENUM ('private', 'unlisted', 'public');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE copy_follow_status AS ENUM ('pending', 'active', 'paused', 'stopped', 'rejected');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE copy_risk_mode AS ENUM ('multiplier', 'fixed_lot', 'fixed_risk_pct');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE copy_event_type AS ENUM ('OPEN', 'CLOSE', 'MODIFY', 'PARTIAL_CLOSE');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE copy_task_status AS ENUM ('queued', 'sent', 'executed', 'failed', 'skipped', 'cancelled');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE copy_trade_side AS ENUM ('BUY', 'SELL');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- admin settings enums
DO $$ BEGIN
  CREATE TYPE contact_type AS ENUM ('support','sales','billing','legal','whatsapp','general','other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE address_type AS ENUM ('registered','corporate','billing','branch','warehouse','other');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE trade_signals_status_type AS ENUM ('pending', 'in_progress', 'completed', 'failed');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;


-- ============================================================
-- COMMON UPDATED_AT TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =================
-- BROKERS
-- =================
CREATE TABLE IF NOT EXISTS brokers (
  id BIGSERIAL PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  market_category market_category NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

DROP TRIGGER IF EXISTS set_timestamp_brokers ON brokers;
CREATE TRIGGER set_timestamp_brokers
BEFORE UPDATE ON brokers
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

INSERT INTO brokers (code, name, market_category) VALUES
('ZERODHA', 'Zerodha', 'INDIAN'),
('MT5', 'MetaTrader 5', 'FOREX'),
('CT', 'cTrader', 'FOREX'),
('ZEBU', 'Zebu', 'INDIAN'),
('DHAN', 'Dhan', 'INDIAN')
ON CONFLICT (code) DO NOTHING;

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
  referral_code TEXT,
  referred_by_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
  allow_trade BOOLEAN DEFAULT TRUE,
  allow_copy_trade BOOLEAN DEFAULT TRUE
);

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS referral_code TEXT;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS referred_by_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique_idx
ON users(LOWER(email)) WHERE email IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_referral_code_nonnull
ON users(referral_code)
WHERE referral_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_referred_by_user_id
ON users(referred_by_user_id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_single_active_admin
ON users ((1))
WHERE is_admin = true
  AND deleted_at IS NULL;

-- ============================================================
-- USER EDGING STATUS
-- ============================================================
CREATE TABLE IF NOT EXISTS user_edging_status (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_edging_status_user_id
ON user_edging_status(user_id);

DROP TRIGGER IF EXISTS trg_user_edging_status_updated_at ON user_edging_status;
CREATE TRIGGER trg_user_edging_status_updated_at
BEFORE UPDATE ON user_edging_status
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- USER RISK LIMITS
-- ============================================================
CREATE TABLE IF NOT EXISTS user_risk_limits (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  daily_loss_limit NUMERIC(15, 2),
  daily_profit_target NUMERIC(15, 2),
  max_trades_per_day INT,
  cooldown_after_loss_mins INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_user_risk_limits_updated_at ON user_risk_limits;
CREATE TRIGGER trg_user_risk_limits_updated_at
BEFORE UPDATE ON user_risk_limits
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- ADMIN STRATEGY TRADE SCHEDULE SETTINGS
-- ============================================================
CREATE TABLE IF NOT EXISTS admin_strategy_trade_schedule_settings (
  id INT PRIMARY KEY,
  is_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata',
  windows JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO admin_strategy_trade_schedule_settings (id, is_enabled, timezone, windows)
VALUES (1, FALSE, 'Asia/Kolkata', '[]'::jsonb)
ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS trg_admin_strategy_trade_schedule_settings_updated_at ON admin_strategy_trade_schedule_settings;
CREATE TRIGGER trg_admin_strategy_trade_schedule_settings_updated_at
BEFORE UPDATE ON admin_strategy_trade_schedule_settings
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

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
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
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
  execution_mode VARCHAR(20),
  entry_ref VARCHAR(100),
  order_type VARCHAR(20),
  limit_price NUMERIC(15, 6),
  stop_price NUMERIC(15, 6),
  stop_loss NUMERIC(15, 6),
  take_profit NUMERIC(15, 6),
  stop_loss_distance NUMERIC(15, 6),
  take_profit_distance NUMERIC(15, 6),
  stop_loss_amount NUMERIC(15, 6),
  take_profit_amount NUMERIC(15, 6),
  trailing_stop_loss BOOLEAN,
  guaranteed_stop_loss BOOLEAN,
  stop_loss_trigger_method VARCHAR(30),
  trailing_take_profit_activation_distance NUMERIC(15, 6),
  trailing_take_profit_distance NUMERIC(15, 6),
  break_even_activation_distance NUMERIC(15, 6),
  break_even_offset_distance NUMERIC(15, 6),
  trailing_stop_loss_distance NUMERIC(15, 6),
  trading_strength NUMERIC(15, 6),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE alert_snapshots
  ADD COLUMN IF NOT EXISTS stop_loss_amount NUMERIC(15, 6);

ALTER TABLE alert_snapshots
  ADD COLUMN IF NOT EXISTS take_profit_amount NUMERIC(15, 6);

ALTER TABLE alert_snapshots
  ADD COLUMN IF NOT EXISTS break_even_activation_distance NUMERIC(15, 6);

ALTER TABLE alert_snapshots
  ADD COLUMN IF NOT EXISTS break_even_offset_distance NUMERIC(15, 6);

ALTER TABLE alert_snapshots
  ADD COLUMN IF NOT EXISTS trailing_stop_loss_distance NUMERIC(15, 6);

DROP TRIGGER IF EXISTS set_timestamp_alert_snapshots ON alert_snapshots;
CREATE TRIGGER set_timestamp_alert_snapshots
BEFORE UPDATE ON alert_snapshots
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- PLAN MODEL (subscription_plans)
-- ============================================================

CREATE TABLE IF NOT EXISTS plan_types (
  id BIGSERIAL PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS markets (
  id BIGSERIAL PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS subscription_plans (
  id BIGSERIAL PRIMARY KEY,
  plan_type_id BIGINT NOT NULL REFERENCES plan_types(id) ON DELETE RESTRICT,
  market_id BIGINT REFERENCES markets(id) ON DELETE RESTRICT,
  name TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  admin_webhook_token TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);



CREATE INDEX IF NOT EXISTS idx_subscription_plans_type ON subscription_plans(plan_type_id);
CREATE INDEX IF NOT EXISTS idx_subscription_plans_market ON subscription_plans(market_id);
CREATE INDEX IF NOT EXISTS idx_subscription_plans_active ON subscription_plans(is_active);
CREATE UNIQUE INDEX IF NOT EXISTS uq_subscription_plans_admin_webhook_token
ON subscription_plans(admin_webhook_token)
WHERE admin_webhook_token IS NOT NULL;

DROP TRIGGER IF EXISTS set_timestamp_subscription_plans ON subscription_plans;
CREATE TRIGGER set_timestamp_subscription_plans
BEFORE UPDATE ON subscription_plans
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS plan_pricing (
  id BIGSERIAL PRIMARY KEY,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  price_inr INT NOT NULL CHECK (price_inr >= 0),
  currency VARCHAR(10) NOT NULL DEFAULT 'INR',
  interval billing_interval NOT NULL DEFAULT 'monthly',
  is_free BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(plan_id)
);

DROP TRIGGER IF EXISTS set_timestamp_plan_pricing ON plan_pricing;
CREATE TRIGGER set_timestamp_plan_pricing
BEFORE UPDATE ON plan_pricing
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS plan_limits (
  id BIGSERIAL PRIMARY KEY,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  min_balance NUMERIC(14,2),
  max_trades_per_week INT,
  max_connected_accounts INT,
  max_daily_trades INT,
  max_lot_per_trade NUMERIC(12,4),
  max_copy_masters INT,
  max_copy_following_accounts INT,
  max_copy_followers_per_master INT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(plan_id)
);

DROP TRIGGER IF EXISTS set_timestamp_plan_limits ON plan_limits;
CREATE TRIGGER set_timestamp_plan_limits
BEFORE UPDATE ON plan_limits
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS plan_features (
  id BIGSERIAL PRIMARY KEY,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  feature_key TEXT NOT NULL,
  feature_value TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(plan_id, feature_key)
);

CREATE TABLE IF NOT EXISTS plan_bundle_items (
  id BIGSERIAL PRIMARY KEY,
  bundle_plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  included_plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  quantity INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(bundle_plan_id, included_plan_id),
  CONSTRAINT chk_bundle_not_self CHECK (bundle_plan_id <> included_plan_id)
);

CREATE INDEX IF NOT EXISTS idx_bundle_items_bundle ON plan_bundle_items(bundle_plan_id);

-- ============================================================
-- USER SUBSCRIPTIONS (plan_id UUID -> subscription_plans)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_subscriptions (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,

  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'past_due', 'canceled', 'expired')),

  status_v2 subscription_status,

  start_date TIMESTAMPTZ NOT NULL DEFAULT now(),
  end_date TIMESTAMPTZ,
  cancel_at TIMESTAMPTZ,
  canceled_at TIMESTAMPTZ,

  auto_renew BOOLEAN DEFAULT TRUE,
  webhook_token TEXT,
  execution_enabled BOOLEAN DEFAULT TRUE,
  liquidate_only_until TIMESTAMPTZ,

  metadata JSONB,
  is_webhook_enabled BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE user_subscriptions ADD COLUMN IF NOT EXISTS is_webhook_enabled BOOLEAN DEFAULT FALSE;

UPDATE user_subscriptions
SET status_v2 =
  COALESCE(status_v2,
    CASE status
      WHEN 'active' THEN 'active'::subscription_status
      WHEN 'past_due' THEN 'past_due'::subscription_status
      WHEN 'canceled' THEN 'canceled'::subscription_status
      WHEN 'expired' THEN 'expired'::subscription_status
      ELSE 'active'::subscription_status
    END
  )
WHERE status_v2 IS NULL;

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
-- SUBSCRIPTION INVOICES / PAYMENTS (plan_id UUID -> subscription_plans)
-- ============================================================
CREATE TABLE IF NOT EXISTS subscription_invoices (
  id BIGSERIAL PRIMARY KEY,
  subscription_id BIGINT NOT NULL REFERENCES user_subscriptions(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,

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
-- STRATEGIES + PLAN_STRATEGIES
-- ============================================================
CREATE TABLE IF NOT EXISTS strategies (
  id BIGSERIAL PRIMARY KEY,
  strategy_code TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  category market_category NOT NULL,
  version INT NOT NULL DEFAULT 1,
  default_params JSONB NOT NULL DEFAULT '{}'::jsonb,
  risk_profile TEXT,
  capital_requirement NUMERIC(12,2),
  is_active BOOLEAN DEFAULT TRUE,
  is_deprecated BOOLEAN DEFAULT FALSE,
  is_copyable BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_strategies_category ON strategies(category);
CREATE INDEX IF NOT EXISTS idx_strategies_active ON strategies(is_active);
CREATE INDEX IF NOT EXISTS idx_strategies_deprecated ON strategies(is_deprecated);
CREATE INDEX IF NOT EXISTS idx_strategies_copyable ON strategies(is_copyable);

DROP TRIGGER IF EXISTS set_timestamp_strategies ON strategies;
CREATE TRIGGER set_timestamp_strategies
BEFORE UPDATE ON strategies
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS plan_strategies (
  id BIGSERIAL PRIMARY KEY,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE CASCADE,
  strategy_id BIGINT NOT NULL REFERENCES strategies(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(plan_id, strategy_id)
);

CREATE INDEX IF NOT EXISTS idx_plan_strategies_plan ON plan_strategies(plan_id);
CREATE INDEX IF NOT EXISTS idx_plan_strategies_strategy ON plan_strategies(strategy_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_plan_strategies_plan_id
ON plan_strategies(plan_id);

-- ============================================================
-- ADMIN STRATEGY TRADE PARENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS admin_strategy_trades (
  id BIGSERIAL PRIMARY KEY,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
  strategy_id BIGINT NOT NULL REFERENCES strategies(id) ON DELETE RESTRICT,
  placed_by_admin_user_id BIGINT REFERENCES users(id) ON DELETE SET NULL,
  source VARCHAR(30) NOT NULL DEFAULT 'plan_webhook',
  action VARCHAR(10) NOT NULL,
  symbol VARCHAR(20) NOT NULL,
  exchange VARCHAR(50),
  price NUMERIC(30, 8),
  execution_mode VARCHAR(20),
  entry_ref VARCHAR(100),
  order_type VARCHAR(20),
  limit_price NUMERIC(15, 6),
  stop_price NUMERIC(15, 6),
  stop_loss NUMERIC(15, 6),
  take_profit NUMERIC(15, 6),
  stop_loss_distance NUMERIC(15, 6),
  take_profit_distance NUMERIC(15, 6),
  stop_loss_amount NUMERIC(15, 6),
  take_profit_amount NUMERIC(15, 6),
  trailing_stop_loss BOOLEAN,
  guaranteed_stop_loss BOOLEAN,
  stop_loss_trigger_method VARCHAR(30),
  trailing_take_profit_activation_distance NUMERIC(15, 6),
  trailing_take_profit_distance NUMERIC(15, 6),
  break_even_activation_distance NUMERIC(15, 6),
  break_even_offset_distance NUMERIC(15, 6),
  trailing_stop_loss_distance NUMERIC(15, 6),
  trading_strength NUMERIC(15, 6),
  raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  execution_allowed BOOLEAN NOT NULL DEFAULT FALSE,
  schedule_blocked BOOLEAN NOT NULL DEFAULT FALSE,
  schedule_window_ids JSONB NOT NULL DEFAULT '[]'::jsonb,
  recipient_count INT NOT NULL DEFAULT 0,
  snapshot_count INT NOT NULL DEFAULT 0,
  signal_count INT NOT NULL DEFAULT 0,
  close_queued_count INT NOT NULL DEFAULT 0,
  status VARCHAR(30) NOT NULL DEFAULT 'received'
    CHECK (status IN ('received', 'blocked', 'fanned_out', 'no_signals', 'close_requested')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_strategy_trades_strategy_created_at
ON admin_strategy_trades(strategy_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_strategy_trades_plan_created_at
ON admin_strategy_trades(plan_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_strategy_trades_status_created_at
ON admin_strategy_trades(status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_strategy_trades_entry_ref
ON admin_strategy_trades(entry_ref);

DROP TRIGGER IF EXISTS set_timestamp_admin_strategy_trades ON admin_strategy_trades;
CREATE TRIGGER set_timestamp_admin_strategy_trades
BEFORE UPDATE ON admin_strategy_trades
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

ALTER TABLE alert_snapshots
  ADD COLUMN IF NOT EXISTS admin_strategy_trade_id BIGINT REFERENCES admin_strategy_trades(id) ON DELETE SET NULL;

ALTER TABLE alert_snapshots
  ADD COLUMN IF NOT EXISTS strategy_id BIGINT REFERENCES strategies(id) ON DELETE SET NULL;

ALTER TABLE alert_snapshots
  ADD COLUMN IF NOT EXISTS plan_id BIGINT REFERENCES subscription_plans(id) ON DELETE SET NULL;

ALTER TABLE alert_snapshots
  ADD COLUMN IF NOT EXISTS subscription_id BIGINT REFERENCES user_subscriptions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_alert_snapshots_admin_strategy_trade_id
ON alert_snapshots(admin_strategy_trade_id);

CREATE INDEX IF NOT EXISTS idx_alert_snapshots_strategy_created_at
ON alert_snapshots(strategy_id, created_at DESC);

-- ============================================================
-- USER TRADING ACCOUNTS + STRATEGY INSTANCES + HEARTBEATS
-- ============================================================
CREATE TABLE IF NOT EXISTS user_trading_accounts (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subscription_id BIGINT REFERENCES user_subscriptions(id) ON DELETE SET NULL,
  broker_id BIGINT NOT NULL REFERENCES brokers(id) ON DELETE RESTRICT,
  account_id TEXT NOT NULL UNIQUE,
  is_master BOOLEAN NOT NULL DEFAULT FALSE,
  execution_flow execution_flow NOT NULL DEFAULT 'API',
  account_label TEXT,
  account_meta JSONB DEFAULT '{}'::jsonb,
  credentials_encrypted TEXT NOT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  status trading_account_status NOT NULL DEFAULT 'pending',
  access_token TEXT,
  refresh_token TEXT,
  last_verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE user_trading_accounts
  ADD COLUMN IF NOT EXISTS subscription_id BIGINT REFERENCES user_subscriptions(id) ON DELETE SET NULL;

ALTER TABLE user_trading_accounts
  ADD COLUMN IF NOT EXISTS execution_flow execution_flow NOT NULL DEFAULT 'API';

ALTER TABLE user_trading_accounts
  ADD COLUMN IF NOT EXISTS is_enabled BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE user_trading_accounts
SET is_enabled = TRUE
WHERE is_enabled IS NULL;


CREATE UNIQUE INDEX uniq_master_per_user_broker
ON user_trading_accounts (user_id, broker_id)
WHERE is_master = true;


CREATE INDEX IF NOT EXISTS idx_user_trading_accounts_user ON user_trading_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_user_trading_accounts_subscription ON user_trading_accounts(subscription_id);
CREATE INDEX IF NOT EXISTS idx_user_trading_accounts_broker ON user_trading_accounts(broker_id);
CREATE INDEX IF NOT EXISTS idx_user_trading_accounts_status ON user_trading_accounts(status);
CREATE INDEX IF NOT EXISTS idx_user_trading_accounts_is_enabled ON user_trading_accounts(is_enabled);

DROP TRIGGER IF EXISTS set_timestamp_user_trading_accounts ON user_trading_accounts;
CREATE TRIGGER set_timestamp_user_trading_accounts
BEFORE UPDATE ON user_trading_accounts
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- TRADE SIGNALS
-- ============================================================
CREATE TABLE IF NOT EXISTS trade_signals (
  id SERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trading_account_id BIGINT NOT NULL REFERENCES user_trading_accounts(id) ON DELETE CASCADE,
  alert_snapshots_id INT REFERENCES alert_snapshots(id) ON DELETE SET NULL,
  action VARCHAR(10) NOT NULL,
  symbol VARCHAR(20) NOT NULL,
  price NUMERIC(30, 8) NOT NULL,
  exchange VARCHAR(50) NOT NULL,
  volume NUMERIC(30, 2) NOT NULL,
  asset_type trade_category NOT NULL,
  signal_time TIMESTAMPTZ NOT NULL,
  order_id BIGINT,
  execution_mode VARCHAR(20),
  entry_ref VARCHAR(100),
  order_type VARCHAR(20),
  limit_price NUMERIC(15, 6),
  stop_price NUMERIC(15, 6),
  stop_loss NUMERIC(15, 6),
  take_profit NUMERIC(15, 6),
  stop_loss_distance NUMERIC(15, 6),
  take_profit_distance NUMERIC(15, 6),
  stop_loss_amount NUMERIC(15, 6),
  take_profit_amount NUMERIC(15, 6),
  trailing_stop_loss BOOLEAN,
  guaranteed_stop_loss BOOLEAN,
  stop_loss_trigger_method VARCHAR(30),
  trailing_take_profit_activation_distance NUMERIC(15, 6),
  trailing_take_profit_distance NUMERIC(15, 6),
  break_even_activation_distance NUMERIC(15, 6),
  break_even_offset_distance NUMERIC(15, 6),
  trailing_stop_loss_distance NUMERIC(15, 6),
  broker_order_id BIGINT,
  broker_position_id BIGINT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS execution_mode VARCHAR(20);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS entry_ref VARCHAR(100);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS order_type VARCHAR(20);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS limit_price NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS stop_price NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS stop_loss NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS take_profit NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS stop_loss_distance NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS take_profit_distance NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS stop_loss_amount NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS take_profit_amount NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS trailing_stop_loss BOOLEAN;

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS guaranteed_stop_loss BOOLEAN;

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS stop_loss_trigger_method VARCHAR(30);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS trailing_take_profit_activation_distance NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS trailing_take_profit_distance NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS break_even_activation_distance NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS break_even_offset_distance NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS trailing_stop_loss_distance NUMERIC(15, 6);

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS broker_order_id BIGINT;

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS broker_position_id BIGINT;

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS admin_strategy_trade_id BIGINT REFERENCES admin_strategy_trades(id) ON DELETE SET NULL;

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS strategy_id BIGINT REFERENCES strategies(id) ON DELETE SET NULL;

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS plan_id BIGINT REFERENCES subscription_plans(id) ON DELETE SET NULL;

ALTER TABLE trade_signals
  ADD COLUMN IF NOT EXISTS subscription_id BIGINT REFERENCES user_subscriptions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_trade_signals_trading_account_entry_ref_created_at
ON trade_signals(trading_account_id, entry_ref, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_trade_signals_entry_ref_execution_mode
ON trade_signals(entry_ref, execution_mode);

CREATE INDEX IF NOT EXISTS idx_trade_signals_admin_strategy_trade_created_at
ON trade_signals(admin_strategy_trade_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_trade_signals_strategy_created_at
ON trade_signals(strategy_id, created_at DESC);

DROP TRIGGER IF EXISTS set_timestamp_trade_signals ON trade_signals;
CREATE TRIGGER set_timestamp_trade_signals
BEFORE UPDATE ON trade_signals
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS trade_signals_status (
  id SERIAL PRIMARY KEY,
  signal_id INT NOT NULL REFERENCES trade_signals(id) ON DELETE CASCADE,  
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'completed', 'failed', 'closed', 'pending_close')),
  attempts INT NOT NULL DEFAULT 0,
  last_error TEXT,
  next_retry_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE trade_signals_status
  ADD COLUMN IF NOT EXISTS last_error TEXT;

ALTER TABLE trade_signals_status
  ADD COLUMN IF NOT EXISTS next_retry_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_trade_signals_status_status_next_retry_at
ON trade_signals_status(status, next_retry_at);

DROP TRIGGER IF EXISTS set_timestamp_trade_signals_status ON trade_signals_status;
CREATE TRIGGER set_timestamp_trade_signals_status
BEFORE UPDATE ON trade_signals_status
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();


CREATE TABLE IF NOT EXISTS user_strategy_instances (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subscription_id BIGINT NOT NULL REFERENCES user_subscriptions(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
  strategy_id BIGINT NOT NULL REFERENCES strategies(id) ON DELETE RESTRICT,
  trading_account_id BIGINT REFERENCES user_trading_accounts(id) ON DELETE SET NULL,
  status user_strategy_status NOT NULL DEFAULT 'active',
  strategy_version INT NOT NULL,
  frozen_params JSONB NOT NULL DEFAULT '{}'::jsonb,
  volume NUMERIC(4,2) NOT NULL DEFAULT 0.01 CHECK (volume >= 0.01 AND volume <= 0.10),
  activated_at TIMESTAMPTZ DEFAULT now(),
  paused_at TIMESTAMPTZ,
  stopped_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_strategy_subscription_strategy
ON user_strategy_instances(subscription_id, strategy_id);

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

CREATE TABLE IF NOT EXISTS ctrader_trailing_take_profit_monitors (
  id BIGSERIAL PRIMARY KEY,
  trade_signal_id BIGINT NOT NULL UNIQUE REFERENCES trade_signals(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trading_account_id BIGINT NOT NULL REFERENCES user_trading_accounts(id) ON DELETE CASCADE,
  account_id BIGINT NOT NULL,
  env VARCHAR(10) NOT NULL CHECK (env IN ('demo', 'live')),
  symbol VARCHAR(50) NOT NULL,
  side VARCHAR(10) NOT NULL CHECK (side IN ('BUY', 'SELL')),
  entry_ref VARCHAR(100) NOT NULL,
  symbol_id INTEGER,
  broker_order_id BIGINT,
  broker_position_id BIGINT,
  entry_price NUMERIC(15, 6),
  trailing_take_profit_activation_distance NUMERIC(15, 6),
  trailing_take_profit_distance NUMERIC(15, 6),
  best_price NUMERIC(15, 6),
  armed BOOLEAN NOT NULL DEFAULT FALSE,
  break_even_activation_distance NUMERIC(15, 6),
  break_even_offset_distance NUMERIC(15, 6),
  trailing_stop_loss_distance NUMERIC(15, 6),
  stop_loss_protection_armed BOOLEAN NOT NULL DEFAULT FALSE,
  stop_loss_best_price NUMERIC(15, 6),
  current_stop_loss NUMERIC(15, 6),
  monitor_status VARCHAR(20) NOT NULL DEFAULT 'pending_fill'
    CHECK (monitor_status IN ('pending_fill', 'active', 'closing', 'completed', 'failed', 'disabled')),
  last_error TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE ctrader_trailing_take_profit_monitors
  ALTER COLUMN trailing_take_profit_activation_distance DROP NOT NULL;

ALTER TABLE ctrader_trailing_take_profit_monitors
  ALTER COLUMN trailing_take_profit_distance DROP NOT NULL;

ALTER TABLE ctrader_trailing_take_profit_monitors
  ADD COLUMN IF NOT EXISTS break_even_activation_distance NUMERIC(15, 6);

ALTER TABLE ctrader_trailing_take_profit_monitors
  ADD COLUMN IF NOT EXISTS break_even_offset_distance NUMERIC(15, 6);

ALTER TABLE ctrader_trailing_take_profit_monitors
  ADD COLUMN IF NOT EXISTS trailing_stop_loss_distance NUMERIC(15, 6);

ALTER TABLE ctrader_trailing_take_profit_monitors
  ADD COLUMN IF NOT EXISTS stop_loss_protection_armed BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE ctrader_trailing_take_profit_monitors
  ADD COLUMN IF NOT EXISTS stop_loss_best_price NUMERIC(15, 6);

ALTER TABLE ctrader_trailing_take_profit_monitors
  ADD COLUMN IF NOT EXISTS current_stop_loss NUMERIC(15, 6);

CREATE INDEX IF NOT EXISTS idx_ctrader_ttp_monitors_status_updated_at
ON ctrader_trailing_take_profit_monitors(monitor_status, updated_at DESC);

DROP TRIGGER IF EXISTS set_timestamp_ctrader_trailing_take_profit_monitors ON ctrader_trailing_take_profit_monitors;
CREATE TRIGGER set_timestamp_ctrader_trailing_take_profit_monitors
BEFORE UPDATE ON ctrader_trailing_take_profit_monitors
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS zebu_protection_monitors (
  id BIGSERIAL PRIMARY KEY,
  trade_signal_id BIGINT NOT NULL UNIQUE REFERENCES trade_signals(id) ON DELETE CASCADE,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trading_account_id BIGINT NOT NULL REFERENCES user_trading_accounts(id) ON DELETE CASCADE,
  symbol VARCHAR(80) NOT NULL,
  exchange VARCHAR(20) NOT NULL,
  side VARCHAR(10) NOT NULL CHECK (side IN ('BUY', 'SELL')),
  entry_ref VARCHAR(100),
  quantity NUMERIC(20, 6) NOT NULL,
  product VARCHAR(20),
  validity VARCHAR(20),
  entry_order_id BIGINT NOT NULL,
  stop_order_id BIGINT,
  target_order_id BIGINT,
  token VARCHAR(60),
  tick_size NUMERIC(18, 8),
  entry_price NUMERIC(15, 6),
  stop_loss NUMERIC(15, 6),
  take_profit NUMERIC(15, 6),
  stop_loss_distance NUMERIC(15, 6),
  take_profit_distance NUMERIC(15, 6),
  break_even_activation_distance NUMERIC(15, 6),
  break_even_offset_distance NUMERIC(15, 6),
  trailing_stop_loss_distance NUMERIC(15, 6),
  current_stop_price NUMERIC(15, 6),
  best_price NUMERIC(15, 6),
  monitor_status VARCHAR(20) NOT NULL DEFAULT 'pending_fill'
    CHECK (monitor_status IN ('pending_fill', 'active', 'closing', 'completed', 'failed', 'disabled')),
  last_error TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_zebu_protection_monitors_status_updated_at
ON zebu_protection_monitors(monitor_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_zebu_protection_monitors_account_symbol
ON zebu_protection_monitors(trading_account_id, symbol, exchange);

DROP TRIGGER IF EXISTS set_timestamp_zebu_protection_monitors ON zebu_protection_monitors;
CREATE TRIGGER set_timestamp_zebu_protection_monitors
BEFORE UPDATE ON zebu_protection_monitors
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

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
-- USER BILLING DETAILS  ✅ (MISSING IN YOUR ERROR)
-- ============================================================
CREATE TABLE IF NOT EXISTS user_billing_details (
  id              BIGSERIAL PRIMARY KEY,
  user_id         BIGINT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  pan_number      VARCHAR(10),
  account_holder_name VARCHAR(120),
  account_number  VARCHAR(34),
  ifsc_code        VARCHAR(11),
  bank_name        VARCHAR(120),
  branch           VARCHAR(120),
  address_line1   VARCHAR(255),
  address_line2   VARCHAR(255),
  city            VARCHAR(80),
  state           VARCHAR(80),
  pincode         VARCHAR(10),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT pan_format_chk CHECK (pan_number IS NULL OR pan_number ~ '^[A-Z]{5}[0-9]{4}[A-Z]{1}$'),
  CONSTRAINT ifsc_format_chk CHECK (ifsc_code IS NULL OR ifsc_code ~ '^[A-Z]{4}0[A-Z0-9]{6}$')
);

DROP TRIGGER IF EXISTS trg_user_billing_updated_at ON user_billing_details;
CREATE TRIGGER trg_user_billing_updated_at
BEFORE UPDATE ON user_billing_details
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- ADMIN SETTINGS
-- ============================================================
CREATE TABLE IF NOT EXISTS admin_settings (
  id              BIGSERIAL PRIMARY KEY,
  organization_id BIGINT UNIQUE,
  title           VARCHAR(150) NOT NULL DEFAULT '',
  description     TEXT NOT NULL DEFAULT '',
  logo_url        TEXT,
  privacy_policy        TEXT NOT NULL DEFAULT '',
  refund_policy         TEXT NOT NULL DEFAULT '',
  agreement             TEXT NOT NULL DEFAULT '',
  terms_and_conditions  TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_admin_settings_updated_at ON admin_settings;
CREATE TRIGGER trg_admin_settings_updated_at
BEFORE UPDATE ON admin_settings
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS admin_setting_emails (
  id           BIGSERIAL PRIMARY KEY,
  settings_id  BIGINT NOT NULL REFERENCES admin_settings(id) ON DELETE CASCADE,
  type         contact_type NOT NULL DEFAULT 'support',
  email        VARCHAR(320) NOT NULL,
  label        VARCHAR(120),
  is_primary   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_setting_primary_email
ON admin_setting_emails(settings_id) WHERE is_primary = TRUE;

CREATE UNIQUE INDEX IF NOT EXISTS uq_setting_email_unique
ON admin_setting_emails(settings_id, type, lower(email));

DROP TRIGGER IF EXISTS trg_setting_emails_updated_at ON admin_setting_emails;
CREATE TRIGGER trg_setting_emails_updated_at
BEFORE UPDATE ON admin_setting_emails
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS admin_setting_phones (
  id           BIGSERIAL PRIMARY KEY,
  settings_id  BIGINT NOT NULL REFERENCES admin_settings(id) ON DELETE CASCADE,
  type         contact_type NOT NULL DEFAULT 'support',
  country_code VARCHAR(8) NOT NULL DEFAULT '+91',
  number       VARCHAR(32) NOT NULL,
  label        VARCHAR(120),
  is_primary   BOOLEAN NOT NULL DEFAULT FALSE,
  is_whatsapp  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_setting_primary_phone
ON admin_setting_phones(settings_id) WHERE is_primary = TRUE;

CREATE UNIQUE INDEX IF NOT EXISTS uq_setting_phone_unique
ON admin_setting_phones(settings_id, type, country_code, number);

DROP TRIGGER IF EXISTS trg_setting_phones_updated_at ON admin_setting_phones;
CREATE TRIGGER trg_setting_phones_updated_at
BEFORE UPDATE ON admin_setting_phones
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS admin_setting_addresses (
  id           BIGSERIAL PRIMARY KEY,
  settings_id  BIGINT NOT NULL REFERENCES admin_settings(id) ON DELETE CASCADE,
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
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_setting_addresses_settings_id
ON admin_setting_addresses(settings_id);

DROP TRIGGER IF EXISTS trg_setting_addresses_updated_at ON admin_setting_addresses;
CREATE TRIGGER trg_setting_addresses_updated_at
BEFORE UPDATE ON admin_setting_addresses
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- RAZORPAY ORDERS
-- ============================================================
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

-- ============================================================
-- COPY TRADING ✅ (MISSING IN YOUR ERROR)
-- ============================================================
CREATE TABLE IF NOT EXISTS copy_trading_masters (
  id BIGSERIAL PRIMARY KEY,
  user_trading_account_id BIGINT NOT NULL REFERENCES user_trading_accounts(id) ON DELETE CASCADE,
  master_trading_account_id BIGINT NOT NULL REFERENCES user_trading_accounts(id) ON DELETE CASCADE,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_copy_master_trading_account_active
ON copy_trading_masters(user_trading_account_id, master_trading_account_id)
WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS set_timestamp_copy_trading_masters ON copy_trading_masters;
CREATE TRIGGER set_timestamp_copy_trading_masters
BEFORE UPDATE ON copy_trading_masters
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- trading followers

CREATE TABLE IF NOT EXISTS copy_trading_followers (
  id BIGSERIAL PRIMARY KEY,
  master_id BIGINT NOT NULL REFERENCES user_trading_accounts(id) ON DELETE CASCADE,
  follower_user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  follower_trading_account_id BIGINT NOT NULL REFERENCES user_trading_accounts(id) ON DELETE CASCADE,
  status copy_follow_status NOT NULL DEFAULT 'pending',
  is_approved BOOLEAN NOT NULL DEFAULT FALSE,
  requested_at TIMESTAMPTZ DEFAULT now(),
  approved_at TIMESTAMPTZ,
  paused_at TIMESTAMPTZ,
  stopped_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(master_id, follower_trading_account_id)
);


CREATE INDEX IF NOT EXISTS idx_copy_follows_master ON copy_trading_followers(master_id);
CREATE INDEX IF NOT EXISTS idx_copy_follows_follower_user ON copy_trading_followers(follower_user_id);
CREATE INDEX IF NOT EXISTS idx_copy_follows_status ON copy_trading_followers(status);

DROP TRIGGER IF EXISTS set_timestamp_copy_trading_followers ON copy_trading_followers;
CREATE TRIGGER set_timestamp_copy_trading_followers
BEFORE UPDATE ON copy_trading_followers
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- CTRADER SESSION MANAGEMENT
-- ============================================================

CREATE TABLE IF NOT EXISTS ctrader_sessions (
  id BIGSERIAL PRIMARY KEY,
  user_id VARCHAR(255) NOT NULL UNIQUE,
  env VARCHAR(10) NOT NULL DEFAULT 'demo' CHECK (env IN ('demo', 'live')),
  active_account_id INTEGER,
  access_token_enc TEXT,
  refresh_token_enc TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ctrader_sessions_user_id ON ctrader_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_ctrader_sessions_expires_at ON ctrader_sessions(expires_at);

DROP TRIGGER IF EXISTS set_timestamp_ctrader_sessions ON ctrader_sessions;
CREATE TRIGGER set_timestamp_ctrader_sessions
BEFORE UPDATE ON ctrader_sessions
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- CTRADER SYMBOL CACHE
-- ============================================================

CREATE TABLE IF NOT EXISTS ctrader_symbols (
  id BIGSERIAL PRIMARY KEY,
  user_id VARCHAR(255) NOT NULL,
  env VARCHAR(10) NOT NULL CHECK (env IN ('demo', 'live')),
  account_id INTEGER NOT NULL,
  symbol_name VARCHAR(50) NOT NULL,
  symbol_id INTEGER NOT NULL,
  lot_size BIGINT,
  digits INTEGER,
  pip_position INTEGER,
  sl_distance INTEGER,
  tp_distance INTEGER,
  distance_set_in VARCHAR(40),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ
);

ALTER TABLE ctrader_symbols
  ADD COLUMN IF NOT EXISTS lot_size BIGINT;

CREATE INDEX IF NOT EXISTS idx_ctrader_symbols_composite ON ctrader_symbols(user_id, env, account_id);
CREATE INDEX IF NOT EXISTS idx_ctrader_symbols_symbol_name ON ctrader_symbols(symbol_name);
CREATE INDEX IF NOT EXISTS idx_ctrader_symbols_expires_at ON ctrader_symbols(expires_at);

DROP TRIGGER IF EXISTS set_timestamp_ctrader_symbols ON ctrader_symbols;
CREATE TRIGGER set_timestamp_ctrader_symbols
BEFORE UPDATE ON ctrader_symbols
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- SUPPORT TICKETS
-- ============================================================

CREATE TABLE IF NOT EXISTS support_tickets (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  external_ticket_id VARCHAR(120) NOT NULL UNIQUE,
  crm_ticket_id VARCHAR(120) UNIQUE,
  platform_user_id VARCHAR(120) NOT NULL,
  contact_email CITEXT NOT NULL,
  contact_name TEXT,
  subject VARCHAR(255) NOT NULL,
  status VARCHAR(32) NOT NULL,
  assigned_executive_id VARCHAR(120),
  assigned_executive_name VARCHAR(255),
  last_customer_message_at TIMESTAMPTZ,
  last_agent_reply_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  sync_status VARCHAR(32) NOT NULL DEFAULT 'pending',
  last_sync_error TEXT,
  last_sync_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_user_updated_at
ON support_tickets (user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_tickets_status_updated_at
ON support_tickets (status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_tickets_platform_user_id
ON support_tickets (platform_user_id);

DROP TRIGGER IF EXISTS set_timestamp_support_tickets ON support_tickets;
CREATE TRIGGER set_timestamp_support_tickets
BEFORE UPDATE ON support_tickets
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

CREATE TABLE IF NOT EXISTS support_ticket_messages (
  id SERIAL PRIMARY KEY,
  ticket_id INT NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  external_message_id VARCHAR(120) UNIQUE,
  crm_message_id VARCHAR(120) UNIQUE,
  author_type VARCHAR(32) NOT NULL,
  body TEXT NOT NULL,
  sync_status VARCHAR(32) NOT NULL DEFAULT 'pending',
  last_sync_error TEXT,
  last_sync_at TIMESTAMPTZ,
  emailed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_support_ticket_messages_ticket_created_at
ON support_ticket_messages (ticket_id, created_at);

DROP TRIGGER IF EXISTS set_timestamp_support_ticket_messages ON support_ticket_messages;
CREATE TRIGGER set_timestamp_support_ticket_messages
BEFORE UPDATE ON support_ticket_messages
FOR EACH ROW EXECUTE PROCEDURE trigger_set_timestamp();

-- ============================================================
-- SAMPLE DATA (PLAN MODEL)
-- ============================================================

INSERT INTO plan_types (code, name)
VALUES
  ('STRATEGY', 'Strategy Subscription'),
  ('SELF_TRADE', 'Self Trading Automation'),
  ('COPY_TRADER', 'Copy Trading'),
  ('MASTER', 'Master Trader')
ON CONFLICT (code) DO NOTHING;

INSERT INTO markets (code, name)
VALUES
  ('FOREX', 'Forex'),
  ('CRYPTO', 'Crypto'),
  ('INDIAN', 'Indian Market')
ON CONFLICT (code) DO NOTHING;



CREATE UNIQUE INDEX IF NOT EXISTS uq_user_subscriptions_id_user
ON user_subscriptions(user_id, plan_id)
WHERE status = 'active';
