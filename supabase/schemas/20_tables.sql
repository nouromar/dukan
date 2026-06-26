-- GENERATED structural schema reference — DO NOT EDIT.
-- Regenerate: ./scripts/gen-schema-reference.sh
-- Reflects every migration in supabase/migrations/. Functions, triggers,
-- RLS policies, and grants are NOT here — they live in the migrations.

--
-- Name: adjustment_reason; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.adjustment_reason (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_increase boolean,
    is_system boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT adjustment_reason_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: audit_action_code; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_action_code (
    code text NOT NULL,
    area text NOT NULL,
    description text,
    captures_before boolean DEFAULT false NOT NULL,
    captures_after boolean DEFAULT false NOT NULL,
    requires_reason boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT audit_action_code_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'::text)))
);

--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    actor_user_id uuid,
    action_code text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    entity_ids uuid[],
    before_state jsonb,
    after_state jsonb,
    reason text,
    client_op_id text,
    source text NOT NULL,
    impersonation_session_id uuid,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    original_actor_user_id uuid,
    CONSTRAINT audit_log_source_check CHECK ((source = ANY (ARRAY['mobile'::text, 'shop_admin_web'::text, 'system_admin_web'::text, 'rpc'::text, 'system'::text])))
)
PARTITION BY RANGE (occurred_at);

--
-- Name: audit_log_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log_2026_06 (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    actor_user_id uuid,
    action_code text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    entity_ids uuid[],
    before_state jsonb,
    after_state jsonb,
    reason text,
    client_op_id text,
    source text NOT NULL,
    impersonation_session_id uuid,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    original_actor_user_id uuid,
    CONSTRAINT audit_log_source_check CHECK ((source = ANY (ARRAY['mobile'::text, 'shop_admin_web'::text, 'system_admin_web'::text, 'rpc'::text, 'system'::text])))
);

--
-- Name: audit_log_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log_2026_07 (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    actor_user_id uuid,
    action_code text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    entity_ids uuid[],
    before_state jsonb,
    after_state jsonb,
    reason text,
    client_op_id text,
    source text NOT NULL,
    impersonation_session_id uuid,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    original_actor_user_id uuid,
    CONSTRAINT audit_log_source_check CHECK ((source = ANY (ARRAY['mobile'::text, 'shop_admin_web'::text, 'system_admin_web'::text, 'rpc'::text, 'system'::text])))
);

--
-- Name: audit_log_2026_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log_2026_08 (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    actor_user_id uuid,
    action_code text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid,
    entity_ids uuid[],
    before_state jsonb,
    after_state jsonb,
    reason text,
    client_op_id text,
    source text NOT NULL,
    impersonation_session_id uuid,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    original_actor_user_id uuid,
    CONSTRAINT audit_log_source_check CHECK ((source = ANY (ARRAY['mobile'::text, 'shop_admin_web'::text, 'system_admin_web'::text, 'rpc'::text, 'system'::text])))
);

--
-- Name: audit_summary; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_summary (
    shop_id uuid NOT NULL,
    day date NOT NULL,
    action_code text NOT NULL,
    actor_user_id uuid NOT NULL,
    source text NOT NULL,
    count integer NOT NULL,
    CONSTRAINT audit_summary_count_check CHECK ((count > 0))
);

--
-- Name: capability; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.capability (
    code text NOT NULL,
    label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT capability_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'::text)))
);

--
-- Name: category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.category (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    parent_id uuid,
    name text NOT NULL,
    name_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    shop_id uuid,
    created_by uuid,
    CONSTRAINT category_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT category_name_check CHECK ((length(btrim(name)) > 0))
);

--
-- Name: currency; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.currency (
    code text NOT NULL,
    symbol text NOT NULL,
    decimals integer DEFAULT 2 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT currency_code_check CHECK (((code = upper(code)) AND (code ~ '^[A-Z][A-Z0-9_]*$'::text))),
    CONSTRAINT currency_decimals_check CHECK (((decimals >= 0) AND (decimals <= 4)))
);

--
-- Name: document; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    type_id uuid NOT NULL,
    storage_bucket text NOT NULL,
    storage_path text NOT NULL,
    mime_type text NOT NULL,
    size_bytes integer NOT NULL,
    ocr_status_id uuid NOT NULL,
    ocr_result jsonb,
    uploaded_by uuid DEFAULT auth.uid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT document_check CHECK (((length(btrim(storage_path)) > 0) AND (storage_path ~~ ((shop_id)::text || '/%'::text)))),
    CONSTRAINT document_mime_type_check CHECK ((mime_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text]))),
    CONSTRAINT document_size_bytes_check CHECK (((size_bytes > 0) AND (size_bytes <= 8388608))),
    CONSTRAINT document_storage_bucket_check CHECK ((storage_bucket = 'shop-documents'::text))
);

--
-- Name: document_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.document_type (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT document_type_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: expense_category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.expense_category (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    name_translations jsonb,
    is_active boolean DEFAULT true NOT NULL,
    source_template_item_id uuid,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT expense_category_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT expense_category_name_check CHECK ((length(btrim(name)) > 0))
);

--
-- Name: help_channel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.help_channel (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid,
    channel text NOT NULL,
    value text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT help_channel_channel_check CHECK ((channel = ANY (ARRAY['whatsapp'::text, 'email'::text]))),
    CONSTRAINT help_channel_value_check CHECK ((length(btrim(value)) > 0))
);

--
-- Name: inventory_adjustment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_adjustment (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    reason_id uuid NOT NULL,
    status_id uuid NOT NULL,
    occurred_at timestamp with time zone NOT NULL,
    posted_at timestamp with time zone,
    document_id uuid,
    client_op_id text,
    notes text,
    approved_by uuid,
    created_by uuid DEFAULT auth.uid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: inventory_adjustment_line; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventory_adjustment_line (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    adjustment_id uuid NOT NULL,
    item_id uuid NOT NULL,
    quantity_delta numeric(14,3) NOT NULL,
    unit_cost numeric(14,4),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT inventory_adjustment_line_quantity_delta_check CHECK ((quantity_delta <> (0)::numeric)),
    CONSTRAINT inventory_adjustment_line_unit_cost_check CHECK (((unit_cost IS NULL) OR (unit_cost >= (0)::numeric)))
);

--
-- Name: item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.item (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    category_id uuid NOT NULL,
    base_unit_code text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT item_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: item_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.item_alias (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    item_id uuid NOT NULL,
    alias_text text NOT NULL,
    alias_text_norm text GENERATED ALWAYS AS (lower(btrim(alias_text))) STORED,
    language_code text,
    is_display boolean DEFAULT false NOT NULL,
    source text DEFAULT 'platform'::text NOT NULL,
    weight integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT item_alias_alias_text_check CHECK ((length(btrim(alias_text)) > 0)),
    CONSTRAINT item_alias_source_check CHECK ((source = ANY (ARRAY['platform'::text, 'learned'::text, 'ocr_correction'::text])))
);

--
-- Name: item_barcode; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.item_barcode (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    item_unit_id uuid NOT NULL,
    barcode text NOT NULL,
    symbology text,
    source text DEFAULT 'manufacturer'::text NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT item_barcode_barcode_check CHECK ((length(btrim(barcode)) > 0)),
    CONSTRAINT item_barcode_source_check CHECK ((source = ANY (ARRAY['manufacturer'::text, 'platform'::text, 'learned'::text])))
);

--
-- Name: item_unit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.item_unit (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    item_id uuid NOT NULL,
    unit_code text NOT NULL,
    conversion_to_base numeric(14,6) NOT NULL,
    is_default_sale boolean DEFAULT false NOT NULL,
    is_default_receive boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT item_unit_conversion_to_base_check CHECK ((conversion_to_base > (0)::numeric))
);

--
-- Name: language; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.language (
    code text NOT NULL,
    name text NOT NULL,
    name_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT language_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: location; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.location (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    name text NOT NULL,
    kind_id uuid NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT location_name_check CHECK ((length(btrim(name)) > 0))
);

--
-- Name: location_kind; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.location_kind (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT location_kind_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: mutation_idempotency; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mutation_idempotency (
    shop_id uuid NOT NULL,
    client_op_id text NOT NULL,
    rpc_name text NOT NULL,
    return_value text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: ocr_correction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ocr_correction (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    document_id uuid NOT NULL,
    raw_text text NOT NULL,
    accepted_entity_table text NOT NULL,
    accepted_entity_id uuid,
    confidence numeric(5,4),
    created_by uuid DEFAULT auth.uid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ocr_correction_accepted_entity_table_check CHECK ((accepted_entity_table = ANY (ARRAY['shop_item'::text, 'party'::text, 'expense_category'::text, 'unknown'::text]))),
    CONSTRAINT ocr_correction_confidence_check CHECK (((confidence IS NULL) OR ((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)))),
    CONSTRAINT ocr_correction_raw_text_check CHECK ((length(btrim(raw_text)) > 0))
);

--
-- Name: ocr_job; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ocr_job (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    document_id uuid NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    locked_at timestamp with time zone,
    last_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ocr_job_attempts_check CHECK ((attempts >= 0)),
    CONSTRAINT ocr_job_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'processing'::text, 'success'::text, 'failed'::text])))
);

--
-- Name: ocr_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ocr_status (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ocr_status_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: organization; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    name text NOT NULL,
    plan_code text,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT organization_name_check CHECK ((length(btrim(name)) > 0))
);

--
-- Name: organization_membership; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_membership (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role_id uuid NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: organization_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_role (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT organization_role_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: organization_role_capability; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_role_capability (
    role_id uuid NOT NULL,
    capability_code text NOT NULL
);

--
-- Name: party; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    name text NOT NULL,
    phone text,
    type_id uuid NOT NULL,
    supplier_type_id uuid,
    receivable numeric(14,2) DEFAULT 0 NOT NULL,
    payable numeric(14,2) DEFAULT 0 NOT NULL,
    notes text,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT party_name_check CHECK ((length(btrim(name)) > 0)),
    CONSTRAINT party_payable_check CHECK ((payable >= (0)::numeric)),
    CONSTRAINT party_receivable_check CHECK ((receivable >= (0)::numeric))
);

--
-- Name: party_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_alias (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    party_id uuid NOT NULL,
    alias_text text NOT NULL,
    alias_text_norm text GENERATED ALWAYS AS (lower(btrim(alias_text))) STORED,
    language_code text,
    source text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT party_alias_alias_text_check CHECK ((length(btrim(alias_text)) > 0)),
    CONSTRAINT party_alias_source_check CHECK ((source = ANY (ARRAY['template'::text, 'manual'::text, 'ocr_correction'::text, 'learned'::text])))
);

--
-- Name: party_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.party_type (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT party_type_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: payment; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    party_id uuid,
    direction character(1) NOT NULL,
    amount numeric(14,2) NOT NULL,
    method_id uuid NOT NULL,
    occurred_at timestamp with time zone NOT NULL,
    document_id uuid,
    refund_of_transaction_id uuid,
    client_op_id text,
    notes text,
    created_by uuid DEFAULT auth.uid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payment_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT payment_direction_check CHECK ((direction = ANY (ARRAY['I'::bpchar, 'O'::bpchar])))
);

--
-- Name: payment_allocation; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_allocation (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    payment_id uuid NOT NULL,
    transaction_id uuid NOT NULL,
    amount numeric(14,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payment_allocation_amount_check CHECK ((amount > (0)::numeric))
);

--
-- Name: payment_method; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_method (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payment_method_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: platform_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_config (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    org_id uuid,
    key text NOT NULL,
    value jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid
);

--
-- Name: platform_membership; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_membership (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    role_code text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT platform_membership_role_code_check CHECK ((role_code = ANY (ARRAY['platform_admin'::text, 'support_agent'::text])))
);

--
-- Name: shop; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name text NOT NULL,
    currency_code text NOT NULL,
    timezone text DEFAULT 'Africa/Mogadishu'::text NOT NULL,
    default_language_code text DEFAULT 'en'::text NOT NULL,
    setup_status text DEFAULT 'not_started'::text NOT NULL,
    setup_completed_at timestamp with time zone,
    onboarding_dismissed_at timestamp with time zone,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    scanner_settings jsonb DEFAULT jsonb_build_object('rearm_ms', 800, 'hid_max_inter_key_gap_ms', 50, 'hid_max_burst_window_ms', 200, 'hid_min_burst_length', 4) NOT NULL,
    CONSTRAINT shop_name_check CHECK ((length(btrim(name)) > 0)),
    CONSTRAINT shop_setup_status_check CHECK ((setup_status = ANY (ARRAY['not_started'::text, 'template_applied'::text, 'opening_stock_done'::text, 'ready'::text])))
);

--
-- Name: shop_invite; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_invite (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    phone text,
    role_code text NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '7 days'::interval) NOT NULL,
    accepted_at timestamp with time zone,
    accepted_by_user_id uuid,
    created_by uuid DEFAULT auth.uid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    email text,
    display_name text,
    CONSTRAINT shop_invite_at_least_one_contact CHECK (((phone IS NOT NULL) OR (email IS NOT NULL))),
    CONSTRAINT shop_invite_display_name_check CHECK (((display_name IS NULL) OR (length(btrim(display_name)) > 0))),
    CONSTRAINT shop_invite_email_check CHECK (((email IS NULL) OR (length(btrim(email)) > 0))),
    CONSTRAINT shop_invite_phone_check CHECK ((length(btrim(phone)) > 0))
);

--
-- Name: shop_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_item (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    item_id uuid,
    base_unit_code text NOT NULL,
    category_id uuid,
    current_stock numeric(14,3) DEFAULT 0 NOT NULL,
    avg_cost numeric(14,4) DEFAULT 0 NOT NULL,
    reorder_threshold numeric(14,3),
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    image_path text,
    CONSTRAINT shop_item_avg_cost_check CHECK ((avg_cost >= (0)::numeric)),
    CONSTRAINT shop_item_reorder_threshold_check CHECK (((reorder_threshold IS NULL) OR (reorder_threshold >= (0)::numeric)))
);

--
-- Name: shop_item_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_item_alias (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    shop_item_id uuid NOT NULL,
    alias_text text NOT NULL,
    alias_text_norm text GENERATED ALWAYS AS (lower(btrim(alias_text))) STORED,
    language_code text,
    is_display boolean DEFAULT false NOT NULL,
    source text DEFAULT 'manual'::text NOT NULL,
    weight integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shop_item_alias_alias_text_check CHECK ((length(btrim(alias_text)) > 0)),
    CONSTRAINT shop_item_alias_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'ocr_correction'::text, 'learned'::text])))
);

--
-- Name: shop_item_barcode; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_item_barcode (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    shop_item_unit_id uuid NOT NULL,
    barcode text NOT NULL,
    symbology text,
    is_primary boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shop_item_barcode_barcode_check CHECK ((length(btrim(barcode)) > 0))
);

--
-- Name: shop_item_entry_profile; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_item_entry_profile (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    item_id uuid NOT NULL,
    context text NOT NULL,
    unit_id uuid NOT NULL,
    quantity numeric(14,3) NOT NULL,
    usage_count integer DEFAULT 0 NOT NULL,
    last_unit_amount numeric(14,4),
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shop_item_entry_profile_context_check CHECK ((context = ANY (ARRAY['sale'::text, 'receive'::text]))),
    CONSTRAINT shop_item_entry_profile_last_unit_amount_check CHECK (((last_unit_amount IS NULL) OR (last_unit_amount >= (0)::numeric))),
    CONSTRAINT shop_item_entry_profile_quantity_check CHECK ((quantity > (0)::numeric)),
    CONSTRAINT shop_item_entry_profile_usage_count_check CHECK ((usage_count >= 0))
);

--
-- Name: shop_item_unit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_item_unit (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    shop_item_id uuid NOT NULL,
    item_unit_id uuid,
    unit_code text NOT NULL,
    conversion_to_base numeric(14,6) NOT NULL,
    sale_price numeric(14,2),
    last_cost numeric(14,4),
    is_default_sale boolean DEFAULT false NOT NULL,
    is_default_receive boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shop_item_unit_conversion_to_base_check CHECK ((conversion_to_base > (0)::numeric)),
    CONSTRAINT shop_item_unit_last_cost_check CHECK (((last_cost IS NULL) OR (last_cost >= (0)::numeric))),
    CONSTRAINT shop_item_unit_sale_price_check CHECK (((sale_price IS NULL) OR (sale_price >= (0)::numeric)))
);

--
-- Name: shop_item_usage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_item_usage (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    item_id uuid NOT NULL,
    sale_count integer DEFAULT 0 NOT NULL,
    receive_count integer DEFAULT 0 NOT NULL,
    total_sale_base_quantity numeric(14,3) DEFAULT 0 NOT NULL,
    total_receive_base_quantity numeric(14,3) DEFAULT 0 NOT NULL,
    last_sale_at timestamp with time zone,
    last_receive_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shop_item_usage_receive_count_check CHECK ((receive_count >= 0)),
    CONSTRAINT shop_item_usage_sale_count_check CHECK ((sale_count >= 0)),
    CONSTRAINT shop_item_usage_total_receive_base_quantity_check CHECK ((total_receive_base_quantity >= (0)::numeric)),
    CONSTRAINT shop_item_usage_total_sale_base_quantity_check CHECK ((total_sale_base_quantity >= (0)::numeric))
);

--
-- Name: shop_membership; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_membership (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role_id uuid NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: shop_party_usage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_party_usage (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    party_id uuid NOT NULL,
    sale_count integer DEFAULT 0 NOT NULL,
    receive_count integer DEFAULT 0 NOT NULL,
    payment_count integer DEFAULT 0 NOT NULL,
    last_sale_at timestamp with time zone,
    last_receive_at timestamp with time zone,
    last_payment_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shop_party_usage_payment_count_check CHECK ((payment_count >= 0)),
    CONSTRAINT shop_party_usage_receive_count_check CHECK ((receive_count >= 0)),
    CONSTRAINT shop_party_usage_sale_count_check CHECK ((sale_count >= 0))
);

--
-- Name: shop_role; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_role (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shop_role_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: shop_role_capability; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_role_capability (
    role_id uuid NOT NULL,
    capability_code text NOT NULL
);

--
-- Name: shop_setting; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_setting (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    key text NOT NULL,
    value jsonb NOT NULL,
    source text DEFAULT 'manual'::text NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shop_setting_key_check CHECK (((key = lower(key)) AND (key ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT shop_setting_source_check CHECK ((source = ANY (ARRAY['template'::text, 'manual'::text, 'learned'::text, 'system'::text])))
);

--
-- Name: shop_suggestion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_suggestion (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    screen text NOT NULL,
    context_key text DEFAULT 'global'::text NOT NULL,
    suggestion_type text NOT NULL,
    target_key text NOT NULL,
    item_id uuid,
    party_id uuid,
    expense_category_id uuid,
    payment_method_id uuid,
    unit_id uuid,
    quantity numeric(14,3),
    value_text text,
    source text NOT NULL,
    rank integer NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    usage_count integer DEFAULT 0 NOT NULL,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shop_suggestion_check CHECK ((((suggestion_type = ANY (ARRAY['item'::text, 'supplier_item'::text])) AND (item_id IS NOT NULL)) OR ((suggestion_type = 'quantity'::text) AND (item_id IS NOT NULL) AND (unit_id IS NOT NULL) AND (quantity IS NOT NULL)) OR ((suggestion_type = ANY (ARRAY['customer'::text, 'supplier'::text])) AND (party_id IS NOT NULL)) OR ((suggestion_type = 'expense_category'::text) AND (expense_category_id IS NOT NULL)) OR ((suggestion_type = 'payment_method'::text) AND (payment_method_id IS NOT NULL)))),
    CONSTRAINT shop_suggestion_quantity_check CHECK (((quantity IS NULL) OR (quantity > (0)::numeric))),
    CONSTRAINT shop_suggestion_screen_check CHECK ((screen = ANY (ARRAY['sale'::text, 'receive'::text, 'payment'::text, 'expense'::text, 'dashboard'::text]))),
    CONSTRAINT shop_suggestion_source_check CHECK ((source = ANY (ARRAY['template'::text, 'setup'::text, 'learned'::text, 'manual'::text]))),
    CONSTRAINT shop_suggestion_suggestion_type_check CHECK ((suggestion_type = ANY (ARRAY['item'::text, 'quantity'::text, 'supplier_item'::text, 'customer'::text, 'supplier'::text, 'expense_category'::text, 'payment_method'::text]))),
    CONSTRAINT shop_suggestion_usage_count_check CHECK ((usage_count >= 0))
);

--
-- Name: shop_supplier_item_profile; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_supplier_item_profile (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    supplier_id uuid NOT NULL,
    item_id uuid NOT NULL,
    unit_id uuid NOT NULL,
    receive_count integer DEFAULT 0 NOT NULL,
    total_base_quantity numeric(14,3) DEFAULT 0 NOT NULL,
    last_unit_cost numeric(14,4),
    last_received_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shop_supplier_item_profile_last_unit_cost_check CHECK (((last_unit_cost IS NULL) OR (last_unit_cost >= (0)::numeric))),
    CONSTRAINT shop_supplier_item_profile_receive_count_check CHECK ((receive_count >= 0)),
    CONSTRAINT shop_supplier_item_profile_total_base_quantity_check CHECK ((total_base_quantity >= (0)::numeric))
);

--
-- Name: shop_sync_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shop_sync_audit (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    user_id uuid NOT NULL,
    kind text NOT NULL,
    ran_at timestamp with time zone DEFAULT now() NOT NULL,
    notes text,
    CONSTRAINT shop_sync_audit_kind_check CHECK ((kind = ANY (ARRAY['full'::text, 'delta'::text])))
);

--
-- Name: stock_movement; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stock_movement (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    item_id uuid NOT NULL,
    location_id uuid,
    transaction_line_id uuid,
    inventory_adjustment_line_id uuid,
    quantity_delta numeric(14,3) NOT NULL,
    unit_cost numeric(14,4),
    occurred_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT stock_movement_check CHECK ((((transaction_line_id IS NOT NULL) AND (inventory_adjustment_line_id IS NULL)) OR ((transaction_line_id IS NULL) AND (inventory_adjustment_line_id IS NOT NULL)))),
    CONSTRAINT stock_movement_quantity_delta_check CHECK ((quantity_delta <> (0)::numeric)),
    CONSTRAINT stock_movement_unit_cost_check CHECK (((unit_cost IS NULL) OR (unit_cost >= (0)::numeric)))
);

--
-- Name: supplier_item_unit_cost; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supplier_item_unit_cost (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    party_id uuid NOT NULL,
    shop_item_unit_id uuid NOT NULL,
    last_unit_cost numeric(14,4),
    last_received_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT supplier_item_unit_cost_last_unit_cost_check CHECK (((last_unit_cost IS NULL) OR (last_unit_cost >= (0)::numeric)))
);

--
-- Name: supplier_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supplier_type (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT supplier_type_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT supplier_type_label_check CHECK ((length(btrim(label)) > 0))
);

--
-- Name: template; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    kind text DEFAULT 'shop_starter'::text NOT NULL,
    name text NOT NULL,
    locale_default text NOT NULL,
    currency_default text NOT NULL,
    version integer NOT NULL,
    is_active boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT template_name_check CHECK ((length(btrim(name)) > 0)),
    CONSTRAINT template_version_check CHECK ((version > 0))
);

--
-- Name: template_application; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_application (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    template_id uuid NOT NULL,
    template_version integer NOT NULL,
    applied_by uuid,
    applied_at timestamp with time zone DEFAULT now() NOT NULL,
    merge_strategy text NOT NULL,
    status text DEFAULT 'applied'::text NOT NULL,
    CONSTRAINT template_application_merge_strategy_check CHECK ((merge_strategy = ANY (ARRAY['first_apply'::text, 'merge_update'::text]))),
    CONSTRAINT template_application_status_check CHECK ((status = ANY (ARRAY['applying'::text, 'applied'::text, 'failed'::text]))),
    CONSTRAINT template_application_template_version_check CHECK ((template_version > 0))
);

--
-- Name: template_expense_category; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_expense_category (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    name_translations jsonb,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_expense_category_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT template_expense_category_name_check CHECK ((length(btrim(name)) > 0))
);

--
-- Name: template_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_item (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    item_code text NOT NULL,
    item_id uuid,
    custom_name text,
    base_unit_code_override text,
    default_sale_unit_code_override text,
    default_receive_unit_code_override text,
    suggested_sale_price numeric(14,2),
    reorder_threshold numeric(14,3),
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_item_check CHECK (((item_id IS NOT NULL) OR ((custom_name IS NOT NULL) AND (base_unit_code_override IS NOT NULL)))),
    CONSTRAINT template_item_custom_name_check CHECK (((custom_name IS NULL) OR (length(btrim(custom_name)) > 0))),
    CONSTRAINT template_item_item_code_check CHECK (((item_code = lower(item_code)) AND (item_code ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT template_item_reorder_threshold_check CHECK (((reorder_threshold IS NULL) OR (reorder_threshold >= (0)::numeric))),
    CONSTRAINT template_item_suggested_sale_price_check CHECK (((suggested_sale_price IS NULL) OR (suggested_sale_price >= (0)::numeric)))
);

--
-- Name: template_item_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_item_alias (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    item_code text NOT NULL,
    language_code text,
    alias_text text NOT NULL,
    alias_text_norm text GENERATED ALWAYS AS (lower(btrim(alias_text))) STORED,
    source text DEFAULT 'template'::text NOT NULL,
    is_display boolean DEFAULT false NOT NULL,
    weight integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_item_alias_alias_text_check CHECK ((length(btrim(alias_text)) > 0))
);

--
-- Name: template_item_unit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_item_unit (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    item_code text NOT NULL,
    unit_code text NOT NULL,
    conversion_to_base numeric(14,6) NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_item_unit_conversion_to_base_check CHECK ((conversion_to_base > (0)::numeric))
);

--
-- Name: template_pack; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_pack (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    code text NOT NULL,
    version integer NOT NULL,
    is_required boolean DEFAULT true NOT NULL,
    file_path text NOT NULL,
    checksum text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_pack_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT template_pack_version_check CHECK ((version > 0))
);

--
-- Name: template_pack_application; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_pack_application (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    template_application_id uuid NOT NULL,
    pack_code text NOT NULL,
    pack_version integer NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL,
    status text NOT NULL,
    CONSTRAINT template_pack_application_pack_version_check CHECK ((pack_version > 0)),
    CONSTRAINT template_pack_application_status_check CHECK ((status = ANY (ARRAY['applied'::text, 'skipped'::text, 'failed'::text])))
);

--
-- Name: template_party_alias; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_party_alias (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    party_code text NOT NULL,
    language_code text,
    alias_text text NOT NULL,
    alias_text_norm text GENERATED ALWAYS AS (lower(btrim(alias_text))) STORED,
    source text DEFAULT 'template'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_party_alias_alias_text_check CHECK ((length(btrim(alias_text)) > 0)),
    CONSTRAINT template_party_alias_party_code_check CHECK (((party_code = lower(party_code)) AND (party_code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: template_quantity_suggestion; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_quantity_suggestion (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    item_code text,
    category_code text,
    context text NOT NULL,
    quantity numeric(14,3) NOT NULL,
    unit_code text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_quantity_suggestion_check CHECK (((item_code IS NOT NULL) OR (category_code IS NOT NULL))),
    CONSTRAINT template_quantity_suggestion_context_check CHECK ((context = ANY (ARRAY['sale'::text, 'receive'::text]))),
    CONSTRAINT template_quantity_suggestion_quantity_check CHECK ((quantity > (0)::numeric))
);

--
-- Name: template_quick_action; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_quick_action (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    screen text NOT NULL,
    "position" integer NOT NULL,
    item_code text,
    expense_category_code text,
    label jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_quick_action_check CHECK (((item_code IS NOT NULL) OR (expense_category_code IS NOT NULL) OR (label IS NOT NULL))),
    CONSTRAINT template_quick_action_position_check CHECK (("position" > 0)),
    CONSTRAINT template_quick_action_screen_check CHECK ((screen = ANY (ARRAY['sale'::text, 'receive'::text, 'expense'::text])))
);

--
-- Name: template_setting; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_setting (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    key text NOT NULL,
    value jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_setting_key_check CHECK (((key = lower(key)) AND (key ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: template_supplier_item; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_supplier_item (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    supplier_type_code text NOT NULL,
    item_code text NOT NULL,
    usual_unit_code text,
    cost_entry_mode text,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_supplier_item_cost_entry_mode_check CHECK ((cost_entry_mode = ANY (ARRAY['unit_cost'::text, 'line_total'::text])))
);

--
-- Name: template_supplier_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_supplier_type (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    supplier_type_code text NOT NULL,
    label jsonb,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT template_supplier_type_supplier_type_code_check CHECK (((supplier_type_code = lower(supplier_type_code)) AND (supplier_type_code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: template_unit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.template_unit (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    template_id uuid NOT NULL,
    unit_code text NOT NULL,
    label jsonb,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

--
-- Name: transaction_line; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transaction_line (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    transaction_id uuid NOT NULL,
    line_no integer NOT NULL,
    item_id uuid,
    shop_item_unit_id uuid,
    expense_category_id uuid,
    quantity numeric(14,3),
    unit_id uuid,
    base_quantity numeric(14,3),
    unit_amount numeric(14,4),
    item_name_snapshot text,
    unit_code_snapshot text,
    unit_conversion_to_base_snapshot numeric(14,6),
    line_total numeric(14,2) NOT NULL,
    cogs_unit_cost numeric(14,4),
    cogs_total numeric(14,2),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT transaction_line_base_quantity_check CHECK (((base_quantity IS NULL) OR (base_quantity > (0)::numeric))),
    CONSTRAINT transaction_line_check CHECK ((((item_id IS NOT NULL) AND (shop_item_unit_id IS NOT NULL) AND (expense_category_id IS NULL) AND (quantity IS NOT NULL) AND (unit_id IS NOT NULL) AND (base_quantity IS NOT NULL) AND (item_name_snapshot IS NOT NULL) AND (unit_code_snapshot IS NOT NULL) AND (unit_conversion_to_base_snapshot IS NOT NULL)) OR ((item_id IS NULL) AND (shop_item_unit_id IS NULL) AND (expense_category_id IS NOT NULL) AND (quantity IS NULL) AND (unit_id IS NULL) AND (base_quantity IS NULL) AND (item_name_snapshot IS NULL) AND (unit_code_snapshot IS NULL) AND (unit_conversion_to_base_snapshot IS NULL)))),
    CONSTRAINT transaction_line_cogs_total_check CHECK (((cogs_total IS NULL) OR (cogs_total >= (0)::numeric))),
    CONSTRAINT transaction_line_cogs_unit_cost_check CHECK (((cogs_unit_cost IS NULL) OR (cogs_unit_cost >= (0)::numeric))),
    CONSTRAINT transaction_line_line_no_check CHECK ((line_no > 0)),
    CONSTRAINT transaction_line_line_total_check CHECK ((line_total >= (0)::numeric)),
    CONSTRAINT transaction_line_quantity_check CHECK (((quantity IS NULL) OR (quantity > (0)::numeric))),
    CONSTRAINT transaction_line_unit_amount_check CHECK (((unit_amount IS NULL) OR (unit_amount >= (0)::numeric))),
    CONSTRAINT transaction_line_unit_conversion_to_base_snapshot_check CHECK (((unit_conversion_to_base_snapshot IS NULL) OR (unit_conversion_to_base_snapshot > (0)::numeric)))
);

--
-- Name: transaction_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transaction_status (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT transaction_status_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: transaction_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.transaction_type (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    stock_effect integer NOT NULL,
    party_balance_effect text NOT NULL,
    requires_party boolean DEFAULT false NOT NULL,
    requires_items boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT transaction_type_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text))),
    CONSTRAINT transaction_type_party_balance_effect_check CHECK ((party_balance_effect = ANY (ARRAY['none'::text, 'receivable'::text, 'payable'::text]))),
    CONSTRAINT transaction_type_stock_effect_check CHECK ((stock_effect = ANY (ARRAY['-1'::integer, 0, 1])))
);

--
-- Name: txn; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.txn (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    shop_id uuid NOT NULL,
    type_id uuid NOT NULL,
    status_id uuid NOT NULL,
    party_id uuid,
    occurred_at timestamp with time zone NOT NULL,
    posted_at timestamp with time zone,
    total_amount numeric(14,2) NOT NULL,
    paid_amount numeric(14,2) DEFAULT 0 NOT NULL,
    payment_method_id uuid,
    document_id uuid,
    reverses_transaction_id uuid,
    client_op_id text,
    notes text,
    created_by uuid DEFAULT auth.uid() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT txn_check CHECK ((paid_amount <= total_amount)),
    CONSTRAINT txn_paid_amount_check CHECK ((paid_amount >= (0)::numeric)),
    CONSTRAINT txn_total_amount_check CHECK ((total_amount >= (0)::numeric))
);

--
-- Name: unit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.unit (
    id uuid DEFAULT extensions.gen_random_uuid() NOT NULL,
    code text NOT NULL,
    default_label text NOT NULL,
    label_translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT unit_code_check CHECK (((code = lower(code)) AND (code ~ '^[a-z][a-z0-9_]*$'::text)))
);

--
-- Name: user_preference; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_preference (
    user_id uuid NOT NULL,
    ui_locale text DEFAULT 'en'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_preference_ui_locale_check CHECK ((ui_locale = ANY (ARRAY['en'::text, 'so'::text])))
);

--
-- Name: user_profile; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_profile (
    user_id uuid NOT NULL,
    display_name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_profile_display_name_check CHECK ((length(btrim(display_name)) > 0))
);

--
-- Name: v_cash_position; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_cash_position WITH (security_invoker='true') AS
 WITH cash_flows AS (
         SELECT t.shop_id,
            t.paid_amount AS cash_in,
            (0)::numeric AS cash_out
           FROM ((public.txn t
             JOIN public.transaction_type tt ON (((tt.id = t.type_id) AND (tt.code = 'sale'::text))))
             JOIN public.payment_method pm ON (((pm.id = t.payment_method_id) AND (pm.code = 'cash'::text))))
          WHERE (t.reverses_transaction_id IS NULL)
        UNION ALL
         SELECT t.shop_id,
            (0)::numeric AS cash_in,
            t.total_amount AS cash_out
           FROM ((public.txn t
             JOIN public.transaction_type tt ON (((tt.id = t.type_id) AND (tt.code = 'expense'::text))))
             JOIN public.payment_method pm ON (((pm.id = t.payment_method_id) AND (pm.code = 'cash'::text))))
          WHERE (t.reverses_transaction_id IS NULL)
        UNION ALL
         SELECT p.shop_id,
            p.amount AS cash_in,
            (0)::numeric AS cash_out
           FROM (public.payment p
             JOIN public.payment_method pm ON (((pm.id = p.method_id) AND (pm.code = 'cash'::text))))
          WHERE (p.direction = 'I'::bpchar)
        UNION ALL
         SELECT p.shop_id,
            (0)::numeric AS cash_in,
            p.amount AS cash_out
           FROM (public.payment p
             JOIN public.payment_method pm ON (((pm.id = p.method_id) AND (pm.code = 'cash'::text))))
          WHERE (p.direction = 'O'::bpchar)
        )
 SELECT shop_id,
    (COALESCE(sum(cash_in), (0)::numeric))::numeric(14,2) AS cash_in,
    (COALESCE(sum(cash_out), (0)::numeric))::numeric(14,2) AS cash_out,
    (COALESCE((sum(cash_in) - sum(cash_out)), (0)::numeric))::numeric(14,2) AS cash_balance
   FROM cash_flows
  GROUP BY shop_id;

--
-- Name: v_expense_report; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_expense_report WITH (security_invoker='true') AS
 SELECT t.shop_id,
    t.id AS transaction_id,
    tl.id AS transaction_line_id,
    t.occurred_at,
    ((t.occurred_at AT TIME ZONE s.timezone))::date AS local_date,
    (date_trunc('month'::text, (t.occurred_at AT TIME ZONE s.timezone)))::date AS local_month,
    tl.expense_category_id,
    ec.code AS expense_category_code,
    ec.name AS expense_category_name,
    tl.line_total AS amount,
    t.payment_method_id,
    pm.code AS payment_method_code,
    t.document_id,
    t.client_op_id,
    t.notes,
    t.created_by,
    t.created_at
   FROM ((((((public.txn t
     JOIN public.shop s ON ((s.id = t.shop_id)))
     JOIN public.transaction_type tt ON ((tt.id = t.type_id)))
     JOIN public.transaction_status ts ON ((ts.id = t.status_id)))
     JOIN public.transaction_line tl ON (((tl.shop_id = t.shop_id) AND (tl.transaction_id = t.id))))
     JOIN public.expense_category ec ON (((ec.shop_id = tl.shop_id) AND (ec.id = tl.expense_category_id))))
     LEFT JOIN public.payment_method pm ON ((pm.id = t.payment_method_id)))
  WHERE ((tt.code = 'expense'::text) AND (ts.code = 'posted'::text));

--
-- Name: v_sales_report; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_sales_report WITH (security_invoker='true') AS
 SELECT t.shop_id,
    t.id AS transaction_id,
    t.occurred_at,
    ((t.occurred_at AT TIME ZONE s.timezone))::date AS local_date,
    (date_trunc('month'::text, (t.occurred_at AT TIME ZONE s.timezone)))::date AS local_month,
    t.party_id AS customer_id,
    p.name AS customer_name,
    t.total_amount AS revenue,
    t.paid_amount,
    ((t.total_amount - t.paid_amount))::numeric(14,2) AS unpaid_amount,
    (COALESCE(sum(tl.cogs_total), (0)::numeric))::numeric(14,2) AS cogs_total,
    ((t.total_amount - COALESCE(sum(tl.cogs_total), (0)::numeric)))::numeric(14,2) AS gross_profit,
    count(tl.id) AS line_count,
    t.payment_method_id,
    pm.code AS payment_method_code,
    t.document_id,
    t.client_op_id,
    t.notes,
    t.created_by,
    t.created_at
   FROM ((((((public.txn t
     JOIN public.shop s ON ((s.id = t.shop_id)))
     JOIN public.transaction_type tt ON ((tt.id = t.type_id)))
     JOIN public.transaction_status ts ON ((ts.id = t.status_id)))
     LEFT JOIN public.party p ON (((p.shop_id = t.shop_id) AND (p.id = t.party_id))))
     LEFT JOIN public.payment_method pm ON ((pm.id = t.payment_method_id)))
     LEFT JOIN public.transaction_line tl ON (((tl.shop_id = t.shop_id) AND (tl.transaction_id = t.id))))
  WHERE ((tt.code = 'sale'::text) AND (ts.code = 'posted'::text))
  GROUP BY t.shop_id, t.id, t.occurred_at, s.timezone, t.party_id, p.name, t.total_amount, t.paid_amount, t.payment_method_id, pm.code, t.document_id, t.client_op_id, t.notes, t.created_by, t.created_at;

--
-- Name: v_daily_profit; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_daily_profit WITH (security_invoker='true') AS
 WITH sales AS (
         SELECT v_sales_report.shop_id,
            v_sales_report.local_date,
            sum(v_sales_report.revenue) AS revenue,
            sum(v_sales_report.cogs_total) AS cogs_total,
            sum(v_sales_report.gross_profit) AS gross_profit,
            count(*) AS sale_count
           FROM public.v_sales_report
          GROUP BY v_sales_report.shop_id, v_sales_report.local_date
        ), expenses AS (
         SELECT v_expense_report.shop_id,
            v_expense_report.local_date,
            sum(v_expense_report.amount) AS expense_total,
            count(*) AS expense_count
           FROM public.v_expense_report
          GROUP BY v_expense_report.shop_id, v_expense_report.local_date
        )
 SELECT COALESCE(s.shop_id, e.shop_id) AS shop_id,
    COALESCE(s.local_date, e.local_date) AS local_date,
    (COALESCE(s.revenue, (0)::numeric))::numeric(14,2) AS revenue,
    (COALESCE(s.cogs_total, (0)::numeric))::numeric(14,2) AS cogs_total,
    (COALESCE(s.gross_profit, (0)::numeric))::numeric(14,2) AS gross_profit,
    (COALESCE(e.expense_total, (0)::numeric))::numeric(14,2) AS expense_total,
    ((COALESCE(s.gross_profit, (0)::numeric) - COALESCE(e.expense_total, (0)::numeric)))::numeric(14,2) AS net_profit,
    COALESCE(s.sale_count, (0)::bigint) AS sale_count,
    COALESCE(e.expense_count, (0)::bigint) AS expense_count
   FROM (sales s
     FULL JOIN expenses e ON (((e.shop_id = s.shop_id) AND (e.local_date = s.local_date))));

--
-- Name: v_item_stock_truth; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_item_stock_truth WITH (security_invoker='true') AS
 SELECT si.shop_id,
    si.id AS item_id,
    public.shop_item_display_name(si.id, 'en'::text) AS item_name,
    si.current_stock AS cached_stock,
    (COALESCE(sum(sm.quantity_delta), (0)::numeric))::numeric(14,3) AS ledger_stock,
    ((si.current_stock - COALESCE(sum(sm.quantity_delta), (0)::numeric)))::numeric(14,3) AS stock_variance,
    count(sm.id) AS movement_count
   FROM (public.shop_item si
     LEFT JOIN public.stock_movement sm ON (((sm.shop_id = si.shop_id) AND (sm.item_id = si.id))))
  GROUP BY si.shop_id, si.id, si.current_stock;

--
-- Name: v_monthly_expenses; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_monthly_expenses WITH (security_invoker='true') AS
 SELECT shop_id,
    local_month,
    expense_category_id,
    expense_category_code,
    expense_category_name,
    count(*) AS expense_count,
    (sum(amount))::numeric(14,2) AS expense_total
   FROM public.v_expense_report
  GROUP BY shop_id, local_month, expense_category_id, expense_category_code, expense_category_name;

--
-- Name: v_monthly_profit; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_monthly_profit WITH (security_invoker='true') AS
 SELECT shop_id,
    (date_trunc('month'::text, (local_date)::timestamp without time zone))::date AS local_month,
    (sum(revenue))::numeric(14,2) AS revenue,
    (sum(cogs_total))::numeric(14,2) AS cogs_total,
    (sum(gross_profit))::numeric(14,2) AS gross_profit,
    (sum(expense_total))::numeric(14,2) AS expense_total,
    (sum(net_profit))::numeric(14,2) AS net_profit,
    sum(sale_count) AS sale_count,
    sum(expense_count) AS expense_count
   FROM public.v_daily_profit
  GROUP BY shop_id, ((date_trunc('month'::text, (local_date)::timestamp without time zone))::date);

--
-- Name: v_monthly_sales; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_monthly_sales WITH (security_invoker='true') AS
 SELECT shop_id,
    local_month,
    count(*) AS sale_count,
    (sum(revenue))::numeric(14,2) AS revenue,
    (sum(paid_amount))::numeric(14,2) AS paid_amount,
    (sum(unpaid_amount))::numeric(14,2) AS unpaid_amount,
    (sum(cogs_total))::numeric(14,2) AS cogs_total,
    (sum(gross_profit))::numeric(14,2) AS gross_profit
   FROM public.v_sales_report
  GROUP BY shop_id, local_month;

--
-- Name: v_party_aging; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_party_aging WITH (security_invoker='true') AS
 SELECT t.shop_id,
    t.party_id,
    t.id AS transaction_id,
    tt.code AS transaction_type,
    t.occurred_at,
    s.timezone,
    (((now() AT TIME ZONE s.timezone))::date - ((t.occurred_at AT TIME ZONE s.timezone))::date) AS days_open,
    t.total_amount,
    COALESCE(( SELECT sum(pa.amount) AS sum
           FROM public.payment_allocation pa
          WHERE ((pa.shop_id = t.shop_id) AND (pa.transaction_id = t.id))), (0)::numeric) AS allocated_amount,
    (t.total_amount - COALESCE(( SELECT sum(pa.amount) AS sum
           FROM public.payment_allocation pa
          WHERE ((pa.shop_id = t.shop_id) AND (pa.transaction_id = t.id))), (0)::numeric)) AS outstanding
   FROM (((public.txn t
     JOIN public.transaction_type tt ON ((tt.id = t.type_id)))
     JOIN public.transaction_status ts ON ((ts.id = t.status_id)))
     JOIN public.shop s ON ((s.id = t.shop_id)))
  WHERE ((ts.code = 'posted'::text) AND (tt.code = ANY (ARRAY['sale'::text, 'receive'::text])) AND (t.reverses_transaction_id IS NULL) AND (t.party_id IS NOT NULL) AND (NOT (EXISTS ( SELECT 1
           FROM public.txn rev
          WHERE ((rev.shop_id = t.shop_id) AND (rev.reverses_transaction_id = t.id))))));

--
-- Name: v_party_balance_truth; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_party_balance_truth WITH (security_invoker='true') AS
 WITH txn_outstanding AS (
         SELECT t.shop_id,
            t.party_id,
            tt.code AS txn_type,
            (t.total_amount - COALESCE(( SELECT sum(pa.amount) AS sum
                   FROM public.payment_allocation pa
                  WHERE ((pa.shop_id = t.shop_id) AND (pa.transaction_id = t.id))), (0)::numeric)) AS outstanding
           FROM ((public.txn t
             JOIN public.transaction_type tt ON ((tt.id = t.type_id)))
             JOIN public.transaction_status ts ON ((ts.id = t.status_id)))
          WHERE ((t.party_id IS NOT NULL) AND (ts.code = 'posted'::text) AND (tt.code = ANY (ARRAY['sale'::text, 'receive'::text])) AND (t.reverses_transaction_id IS NULL) AND (NOT (EXISTS ( SELECT 1
                   FROM public.txn rev
                  WHERE ((rev.shop_id = t.shop_id) AND (rev.reverses_transaction_id = t.id))))))
        ), party_outstanding AS (
         SELECT txn_outstanding.shop_id,
            txn_outstanding.party_id,
            sum(
                CASE
                    WHEN (txn_outstanding.txn_type = 'sale'::text) THEN txn_outstanding.outstanding
                    ELSE (0)::numeric
                END) AS ledger_receivable_raw,
            sum(
                CASE
                    WHEN (txn_outstanding.txn_type = 'receive'::text) THEN txn_outstanding.outstanding
                    ELSE (0)::numeric
                END) AS ledger_payable_raw
           FROM txn_outstanding
          GROUP BY txn_outstanding.shop_id, txn_outstanding.party_id
        )
 SELECT p.shop_id,
    p.id AS party_id,
    p.name AS party_name,
    pt.code AS party_type_code,
    p.receivable AS cached_receivable,
    (COALESCE(po.ledger_receivable_raw, (0)::numeric))::numeric(14,2) AS ledger_receivable,
    ((p.receivable - COALESCE(po.ledger_receivable_raw, (0)::numeric)))::numeric(14,2) AS receivable_variance,
    p.payable AS cached_payable,
    (COALESCE(po.ledger_payable_raw, (0)::numeric))::numeric(14,2) AS ledger_payable,
    ((p.payable - COALESCE(po.ledger_payable_raw, (0)::numeric)))::numeric(14,2) AS payable_variance
   FROM ((public.party p
     JOIN public.party_type pt ON ((pt.id = p.type_id)))
     LEFT JOIN party_outstanding po ON (((po.shop_id = p.shop_id) AND (po.party_id = p.id))));

--
-- Name: v_payment_report; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_payment_report WITH (security_invoker='true') AS
 SELECT p.shop_id,
    p.id AS payment_id,
    p.party_id,
    party.name AS party_name,
    p.direction,
    p.amount,
    p.method_id,
    pm.code AS payment_method_code,
    p.occurred_at,
    ((p.occurred_at AT TIME ZONE s.timezone))::date AS local_date,
    (date_trunc('month'::text, (p.occurred_at AT TIME ZONE s.timezone)))::date AS local_month,
    p.document_id,
    p.client_op_id,
    p.notes,
    p.created_by,
    p.created_at
   FROM (((public.payment p
     JOIN public.shop s ON ((s.id = p.shop_id)))
     JOIN public.payment_method pm ON ((pm.id = p.method_id)))
     LEFT JOIN public.party party ON (((party.shop_id = p.shop_id) AND (party.id = p.party_id))));

--
-- Name: v_receive_report; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_receive_report WITH (security_invoker='true') AS
 SELECT t.shop_id,
    t.id AS transaction_id,
    t.occurred_at,
    ((t.occurred_at AT TIME ZONE s.timezone))::date AS local_date,
    (date_trunc('month'::text, (t.occurred_at AT TIME ZONE s.timezone)))::date AS local_month,
    t.party_id AS supplier_id,
    p.name AS supplier_name,
    t.total_amount,
    t.paid_amount,
    ((t.total_amount - t.paid_amount))::numeric(14,2) AS unpaid_amount,
    count(tl.id) AS line_count,
    t.payment_method_id,
    pm.code AS payment_method_code,
    t.document_id,
    t.client_op_id,
    t.notes,
    t.created_by,
    t.created_at
   FROM ((((((public.txn t
     JOIN public.shop s ON ((s.id = t.shop_id)))
     JOIN public.transaction_type tt ON ((tt.id = t.type_id)))
     JOIN public.transaction_status ts ON ((ts.id = t.status_id)))
     LEFT JOIN public.party p ON (((p.shop_id = t.shop_id) AND (p.id = t.party_id))))
     LEFT JOIN public.payment_method pm ON ((pm.id = t.payment_method_id)))
     LEFT JOIN public.transaction_line tl ON (((tl.shop_id = t.shop_id) AND (tl.transaction_id = t.id))))
  WHERE ((tt.code = 'receive'::text) AND (ts.code = 'posted'::text))
  GROUP BY t.shop_id, t.id, t.occurred_at, s.timezone, t.party_id, p.name, t.total_amount, t.paid_amount, t.payment_method_id, pm.code, t.document_id, t.client_op_id, t.notes, t.created_by, t.created_at;

--
-- Name: v_shop_suggestions; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_shop_suggestions WITH (security_invoker='true') AS
 SELECT ss.shop_id,
    ss.id AS suggestion_id,
    ss.screen,
    ss.context_key,
    ss.suggestion_type,
    ss.item_id,
    public.shop_item_display_name(ss.item_id, 'en'::text) AS item_name,
    ss.party_id,
    p.name AS party_name,
    ss.expense_category_id,
    ec.code AS expense_category_code,
    ec.name AS expense_category_name,
    ss.payment_method_id,
    pm.code AS payment_method_code,
    ss.unit_id,
    u.code AS unit_code,
    ss.quantity,
    ss.value_text,
    ss.source,
    ss.rank,
    ss.usage_count,
    ss.last_used_at,
    ss.created_at,
    ss.updated_at
   FROM (((((public.shop_suggestion ss
     LEFT JOIN public.shop_item si ON (((si.shop_id = ss.shop_id) AND (si.id = ss.item_id))))
     LEFT JOIN public.party p ON (((p.shop_id = ss.shop_id) AND (p.id = ss.party_id))))
     LEFT JOIN public.expense_category ec ON (((ec.shop_id = ss.shop_id) AND (ec.id = ss.expense_category_id))))
     LEFT JOIN public.payment_method pm ON ((pm.id = ss.payment_method_id)))
     LEFT JOIN public.unit u ON ((u.id = ss.unit_id)))
  WHERE ss.is_active;

--
-- Name: audit_log_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ATTACH PARTITION public.audit_log_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

--
-- Name: audit_log_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ATTACH PARTITION public.audit_log_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');

--
-- Name: audit_log_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ATTACH PARTITION public.audit_log_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');

