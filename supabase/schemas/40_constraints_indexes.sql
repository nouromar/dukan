-- GENERATED structural schema reference — DO NOT EDIT.
-- Regenerate: ./scripts/gen-schema-reference.sh
-- Reflects every migration in supabase/migrations/. Functions, triggers,
-- RLS policies, and grants are NOT here — they live in the migrations.

--
-- Name: adjustment_reason adjustment_reason_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adjustment_reason
    ADD CONSTRAINT adjustment_reason_code_key UNIQUE (code);

--
-- Name: adjustment_reason adjustment_reason_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.adjustment_reason
    ADD CONSTRAINT adjustment_reason_pkey PRIMARY KEY (id);

--
-- Name: audit_action_code audit_action_code_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_action_code
    ADD CONSTRAINT audit_action_code_pkey PRIMARY KEY (code);

--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (occurred_at, id);

--
-- Name: audit_log_2026_06 audit_log_2026_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log_2026_06
    ADD CONSTRAINT audit_log_2026_06_pkey PRIMARY KEY (occurred_at, id);

--
-- Name: audit_log_2026_07 audit_log_2026_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log_2026_07
    ADD CONSTRAINT audit_log_2026_07_pkey PRIMARY KEY (occurred_at, id);

--
-- Name: audit_log_2026_08 audit_log_2026_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log_2026_08
    ADD CONSTRAINT audit_log_2026_08_pkey PRIMARY KEY (occurred_at, id);

--
-- Name: audit_summary audit_summary_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_summary
    ADD CONSTRAINT audit_summary_pkey PRIMARY KEY (shop_id, day, action_code, actor_user_id, source);

--
-- Name: capability capability_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.capability
    ADD CONSTRAINT capability_pkey PRIMARY KEY (code);

--
-- Name: category category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.category
    ADD CONSTRAINT category_pkey PRIMARY KEY (id);

--
-- Name: currency currency_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.currency
    ADD CONSTRAINT currency_pkey PRIMARY KEY (code);

--
-- Name: document document_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_pkey PRIMARY KEY (id);

--
-- Name: document document_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: document document_storage_bucket_storage_path_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_storage_bucket_storage_path_key UNIQUE (storage_bucket, storage_path);

--
-- Name: document document_storage_path_shape; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.document
    ADD CONSTRAINT document_storage_path_shape CHECK ((storage_path ~* (((('^'::text || (shop_id)::text) || '/documents/'::text) || (id)::text) || '/image\.(jpg|jpeg|png|webp)$'::text))) NOT VALID;

--
-- Name: document_type document_type_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_type
    ADD CONSTRAINT document_type_code_key UNIQUE (code);

--
-- Name: document_type document_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document_type
    ADD CONSTRAINT document_type_pkey PRIMARY KEY (id);

--
-- Name: expense_category expense_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_category
    ADD CONSTRAINT expense_category_pkey PRIMARY KEY (id);

--
-- Name: expense_category expense_category_shop_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_category
    ADD CONSTRAINT expense_category_shop_id_code_key UNIQUE (shop_id, code);

--
-- Name: expense_category expense_category_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_category
    ADD CONSTRAINT expense_category_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: help_channel help_channel_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_channel
    ADD CONSTRAINT help_channel_pkey PRIMARY KEY (id);

--
-- Name: help_channel help_channel_shop_id_channel_value_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_channel
    ADD CONSTRAINT help_channel_shop_id_channel_value_key UNIQUE (shop_id, channel, value);

--
-- Name: help_channel help_channel_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_channel
    ADD CONSTRAINT help_channel_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: inventory_adjustment_line inventory_adjustment_line_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment_line
    ADD CONSTRAINT inventory_adjustment_line_pkey PRIMARY KEY (id);

--
-- Name: inventory_adjustment_line inventory_adjustment_line_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment_line
    ADD CONSTRAINT inventory_adjustment_line_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: inventory_adjustment inventory_adjustment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment
    ADD CONSTRAINT inventory_adjustment_pkey PRIMARY KEY (id);

--
-- Name: inventory_adjustment inventory_adjustment_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment
    ADD CONSTRAINT inventory_adjustment_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: item_alias item_alias_item_id_language_code_alias_text_norm_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_alias
    ADD CONSTRAINT item_alias_item_id_language_code_alias_text_norm_key UNIQUE (item_id, language_code, alias_text_norm);

--
-- Name: item_alias item_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_alias
    ADD CONSTRAINT item_alias_pkey PRIMARY KEY (id);

--
-- Name: item_barcode item_barcode_item_unit_id_barcode_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_barcode
    ADD CONSTRAINT item_barcode_item_unit_id_barcode_key UNIQUE (item_unit_id, barcode);

--
-- Name: item_barcode item_barcode_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_barcode
    ADD CONSTRAINT item_barcode_pkey PRIMARY KEY (id);

--
-- Name: item item_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item
    ADD CONSTRAINT item_code_key UNIQUE (code);

--
-- Name: item item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item
    ADD CONSTRAINT item_pkey PRIMARY KEY (id);

--
-- Name: item_unit item_unit_item_id_unit_code_conversion_to_base_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_unit
    ADD CONSTRAINT item_unit_item_id_unit_code_conversion_to_base_key UNIQUE (item_id, unit_code, conversion_to_base);

--
-- Name: item_unit item_unit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_unit
    ADD CONSTRAINT item_unit_pkey PRIMARY KEY (id);

--
-- Name: language language_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.language
    ADD CONSTRAINT language_pkey PRIMARY KEY (code);

--
-- Name: location_kind location_kind_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location_kind
    ADD CONSTRAINT location_kind_code_key UNIQUE (code);

--
-- Name: location_kind location_kind_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location_kind
    ADD CONSTRAINT location_kind_pkey PRIMARY KEY (id);

--
-- Name: location location_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_pkey PRIMARY KEY (id);

--
-- Name: location location_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: location location_shop_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_shop_id_name_key UNIQUE (shop_id, name);

--
-- Name: mutation_idempotency mutation_idempotency_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mutation_idempotency
    ADD CONSTRAINT mutation_idempotency_pkey PRIMARY KEY (shop_id, client_op_id);

--
-- Name: ocr_correction ocr_correction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_correction
    ADD CONSTRAINT ocr_correction_pkey PRIMARY KEY (id);

--
-- Name: ocr_correction ocr_correction_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_correction
    ADD CONSTRAINT ocr_correction_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: ocr_job ocr_job_document_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_job
    ADD CONSTRAINT ocr_job_document_id_key UNIQUE (document_id);

--
-- Name: ocr_job ocr_job_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_job
    ADD CONSTRAINT ocr_job_pkey PRIMARY KEY (id);

--
-- Name: ocr_job ocr_job_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_job
    ADD CONSTRAINT ocr_job_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: ocr_status ocr_status_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_status
    ADD CONSTRAINT ocr_status_code_key UNIQUE (code);

--
-- Name: ocr_status ocr_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_status
    ADD CONSTRAINT ocr_status_pkey PRIMARY KEY (id);

--
-- Name: organization_membership organization_membership_organization_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_membership
    ADD CONSTRAINT organization_membership_organization_id_id_key UNIQUE (organization_id, id);

--
-- Name: organization_membership organization_membership_organization_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_membership
    ADD CONSTRAINT organization_membership_organization_id_user_id_key UNIQUE (organization_id, user_id);

--
-- Name: organization_membership organization_membership_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_membership
    ADD CONSTRAINT organization_membership_pkey PRIMARY KEY (id);

--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);

--
-- Name: organization_role_capability organization_role_capability_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_role_capability
    ADD CONSTRAINT organization_role_capability_pkey PRIMARY KEY (role_id, capability_code);

--
-- Name: organization_role organization_role_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_role
    ADD CONSTRAINT organization_role_code_key UNIQUE (code);

--
-- Name: organization_role organization_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_role
    ADD CONSTRAINT organization_role_pkey PRIMARY KEY (id);

--
-- Name: party_alias party_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_alias
    ADD CONSTRAINT party_alias_pkey PRIMARY KEY (id);

--
-- Name: party_alias party_alias_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_alias
    ADD CONSTRAINT party_alias_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: party_alias party_alias_shop_id_party_id_language_code_alias_text_norm_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_alias
    ADD CONSTRAINT party_alias_shop_id_party_id_language_code_alias_text_norm_key UNIQUE (shop_id, party_id, language_code, alias_text_norm);

--
-- Name: party party_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party
    ADD CONSTRAINT party_pkey PRIMARY KEY (id);

--
-- Name: party party_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party
    ADD CONSTRAINT party_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: party_type party_type_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_type
    ADD CONSTRAINT party_type_code_key UNIQUE (code);

--
-- Name: party_type party_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_type
    ADD CONSTRAINT party_type_pkey PRIMARY KEY (id);

--
-- Name: payment_allocation payment_allocation_payment_id_transaction_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocation
    ADD CONSTRAINT payment_allocation_payment_id_transaction_id_key UNIQUE (payment_id, transaction_id);

--
-- Name: payment_allocation payment_allocation_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocation
    ADD CONSTRAINT payment_allocation_pkey PRIMARY KEY (id);

--
-- Name: payment_allocation payment_allocation_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocation
    ADD CONSTRAINT payment_allocation_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: payment_method payment_method_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_method
    ADD CONSTRAINT payment_method_code_key UNIQUE (code);

--
-- Name: payment_method payment_method_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_method
    ADD CONSTRAINT payment_method_pkey PRIMARY KEY (id);

--
-- Name: payment payment_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_pkey PRIMARY KEY (id);

--
-- Name: payment payment_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: platform_config platform_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_config
    ADD CONSTRAINT platform_config_pkey PRIMARY KEY (id);

--
-- Name: platform_membership platform_membership_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_membership
    ADD CONSTRAINT platform_membership_pkey PRIMARY KEY (id);

--
-- Name: platform_membership platform_membership_user_id_role_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_membership
    ADD CONSTRAINT platform_membership_user_id_role_code_key UNIQUE (user_id, role_code);

--
-- Name: shop_invite shop_invite_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_invite
    ADD CONSTRAINT shop_invite_pkey PRIMARY KEY (id);

--
-- Name: shop_item_alias shop_item_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_alias
    ADD CONSTRAINT shop_item_alias_pkey PRIMARY KEY (id);

--
-- Name: shop_item_alias shop_item_alias_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_alias
    ADD CONSTRAINT shop_item_alias_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_item_alias shop_item_alias_shop_id_shop_item_id_language_code_alias_te_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_alias
    ADD CONSTRAINT shop_item_alias_shop_id_shop_item_id_language_code_alias_te_key UNIQUE (shop_id, shop_item_id, language_code, alias_text_norm);

--
-- Name: shop_item_barcode shop_item_barcode_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_barcode
    ADD CONSTRAINT shop_item_barcode_pkey PRIMARY KEY (id);

--
-- Name: shop_item_barcode shop_item_barcode_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_barcode
    ADD CONSTRAINT shop_item_barcode_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_item_barcode shop_item_barcode_shop_id_shop_item_unit_id_barcode_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_barcode
    ADD CONSTRAINT shop_item_barcode_shop_id_shop_item_unit_id_barcode_key UNIQUE (shop_id, shop_item_unit_id, barcode);

--
-- Name: shop_item_entry_profile shop_item_entry_profile_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_entry_profile
    ADD CONSTRAINT shop_item_entry_profile_pkey PRIMARY KEY (id);

--
-- Name: shop_item_entry_profile shop_item_entry_profile_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_entry_profile
    ADD CONSTRAINT shop_item_entry_profile_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_item_entry_profile shop_item_entry_profile_shop_id_item_id_context_unit_id_qua_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_entry_profile
    ADD CONSTRAINT shop_item_entry_profile_shop_id_item_id_context_unit_id_qua_key UNIQUE (shop_id, item_id, context, unit_id, quantity);

--
-- Name: shop_item shop_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item
    ADD CONSTRAINT shop_item_pkey PRIMARY KEY (id);

--
-- Name: shop_item shop_item_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item
    ADD CONSTRAINT shop_item_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_item shop_item_unique_activation; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item
    ADD CONSTRAINT shop_item_unique_activation UNIQUE (shop_id, item_id);

--
-- Name: shop_item_unit shop_item_unit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_unit
    ADD CONSTRAINT shop_item_unit_pkey PRIMARY KEY (id);

--
-- Name: shop_item_unit shop_item_unit_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_unit
    ADD CONSTRAINT shop_item_unit_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_item_usage shop_item_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_usage
    ADD CONSTRAINT shop_item_usage_pkey PRIMARY KEY (id);

--
-- Name: shop_item_usage shop_item_usage_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_usage
    ADD CONSTRAINT shop_item_usage_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_item_usage shop_item_usage_shop_id_item_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_usage
    ADD CONSTRAINT shop_item_usage_shop_id_item_id_key UNIQUE (shop_id, item_id);

--
-- Name: shop_membership shop_membership_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_membership
    ADD CONSTRAINT shop_membership_pkey PRIMARY KEY (id);

--
-- Name: shop_membership shop_membership_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_membership
    ADD CONSTRAINT shop_membership_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_membership shop_membership_shop_id_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_membership
    ADD CONSTRAINT shop_membership_shop_id_user_id_key UNIQUE (shop_id, user_id);

--
-- Name: shop shop_organization_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop
    ADD CONSTRAINT shop_organization_id_id_key UNIQUE (organization_id, id);

--
-- Name: shop_party_usage shop_party_usage_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_party_usage
    ADD CONSTRAINT shop_party_usage_pkey PRIMARY KEY (id);

--
-- Name: shop_party_usage shop_party_usage_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_party_usage
    ADD CONSTRAINT shop_party_usage_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_party_usage shop_party_usage_shop_id_party_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_party_usage
    ADD CONSTRAINT shop_party_usage_shop_id_party_id_key UNIQUE (shop_id, party_id);

--
-- Name: shop shop_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop
    ADD CONSTRAINT shop_pkey PRIMARY KEY (id);

--
-- Name: shop_role_capability shop_role_capability_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_role_capability
    ADD CONSTRAINT shop_role_capability_pkey PRIMARY KEY (role_id, capability_code);

--
-- Name: shop_role shop_role_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_role
    ADD CONSTRAINT shop_role_code_key UNIQUE (code);

--
-- Name: shop_role shop_role_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_role
    ADD CONSTRAINT shop_role_pkey PRIMARY KEY (id);

--
-- Name: shop_setting shop_setting_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_setting
    ADD CONSTRAINT shop_setting_pkey PRIMARY KEY (id);

--
-- Name: shop_setting shop_setting_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_setting
    ADD CONSTRAINT shop_setting_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_setting shop_setting_shop_id_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_setting
    ADD CONSTRAINT shop_setting_shop_id_key_key UNIQUE (shop_id, key);

--
-- Name: shop_suggestion shop_suggestion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_suggestion
    ADD CONSTRAINT shop_suggestion_pkey PRIMARY KEY (id);

--
-- Name: shop_suggestion shop_suggestion_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_suggestion
    ADD CONSTRAINT shop_suggestion_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_suggestion shop_suggestion_shop_id_screen_context_key_suggestion_type__key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_suggestion
    ADD CONSTRAINT shop_suggestion_shop_id_screen_context_key_suggestion_type__key UNIQUE (shop_id, screen, context_key, suggestion_type, target_key, source);

--
-- Name: shop_supplier_item_profile shop_supplier_item_profile_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_supplier_item_profile
    ADD CONSTRAINT shop_supplier_item_profile_pkey PRIMARY KEY (id);

--
-- Name: shop_supplier_item_profile shop_supplier_item_profile_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_supplier_item_profile
    ADD CONSTRAINT shop_supplier_item_profile_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: shop_supplier_item_profile shop_supplier_item_profile_shop_id_supplier_id_item_id_unit_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_supplier_item_profile
    ADD CONSTRAINT shop_supplier_item_profile_shop_id_supplier_id_item_id_unit_key UNIQUE (shop_id, supplier_id, item_id, unit_id);

--
-- Name: shop_sync_audit shop_sync_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_sync_audit
    ADD CONSTRAINT shop_sync_audit_pkey PRIMARY KEY (id);

--
-- Name: stock_movement stock_movement_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movement
    ADD CONSTRAINT stock_movement_pkey PRIMARY KEY (id);

--
-- Name: stock_movement stock_movement_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movement
    ADD CONSTRAINT stock_movement_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: supplier_item_unit_cost supplier_item_unit_cost_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_item_unit_cost
    ADD CONSTRAINT supplier_item_unit_cost_pkey PRIMARY KEY (id);

--
-- Name: supplier_item_unit_cost supplier_item_unit_cost_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_item_unit_cost
    ADD CONSTRAINT supplier_item_unit_cost_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: supplier_item_unit_cost supplier_item_unit_cost_shop_id_party_id_shop_item_unit_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_item_unit_cost
    ADD CONSTRAINT supplier_item_unit_cost_shop_id_party_id_shop_item_unit_id_key UNIQUE (shop_id, party_id, shop_item_unit_id);

--
-- Name: supplier_type supplier_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_type
    ADD CONSTRAINT supplier_type_pkey PRIMARY KEY (id);

--
-- Name: supplier_type supplier_type_shop_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_type
    ADD CONSTRAINT supplier_type_shop_id_code_key UNIQUE (shop_id, code);

--
-- Name: supplier_type supplier_type_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_type
    ADD CONSTRAINT supplier_type_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: template_application template_application_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_application
    ADD CONSTRAINT template_application_pkey PRIMARY KEY (id);

--
-- Name: template_application template_application_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_application
    ADD CONSTRAINT template_application_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: template_application template_application_shop_id_template_id_template_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_application
    ADD CONSTRAINT template_application_shop_id_template_id_template_version_key UNIQUE (shop_id, template_id, template_version);

--
-- Name: template template_code_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template
    ADD CONSTRAINT template_code_version_key UNIQUE (code, version);

--
-- Name: template_expense_category template_expense_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_expense_category
    ADD CONSTRAINT template_expense_category_pkey PRIMARY KEY (id);

--
-- Name: template_expense_category template_expense_category_template_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_expense_category
    ADD CONSTRAINT template_expense_category_template_id_code_key UNIQUE (template_id, code);

--
-- Name: template template_id_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template
    ADD CONSTRAINT template_id_version_key UNIQUE (id, version);

--
-- Name: template_item_alias template_item_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item_alias
    ADD CONSTRAINT template_item_alias_pkey PRIMARY KEY (id);

--
-- Name: template_item_alias template_item_alias_template_id_item_code_language_code_ali_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item_alias
    ADD CONSTRAINT template_item_alias_template_id_item_code_language_code_ali_key UNIQUE (template_id, item_code, language_code, alias_text_norm);

--
-- Name: template_item template_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item
    ADD CONSTRAINT template_item_pkey PRIMARY KEY (id);

--
-- Name: template_item template_item_template_id_item_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item
    ADD CONSTRAINT template_item_template_id_item_code_key UNIQUE (template_id, item_code);

--
-- Name: template_item_unit template_item_unit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item_unit
    ADD CONSTRAINT template_item_unit_pkey PRIMARY KEY (id);

--
-- Name: template_item_unit template_item_unit_template_id_item_code_unit_code_conversi_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item_unit
    ADD CONSTRAINT template_item_unit_template_id_item_code_unit_code_conversi_key UNIQUE (template_id, item_code, unit_code, conversion_to_base);

--
-- Name: template_pack_application template_pack_application_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_pack_application
    ADD CONSTRAINT template_pack_application_pkey PRIMARY KEY (id);

--
-- Name: template_pack_application template_pack_application_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_pack_application
    ADD CONSTRAINT template_pack_application_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: template_pack_application template_pack_application_template_application_id_pack_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_pack_application
    ADD CONSTRAINT template_pack_application_template_application_id_pack_code_key UNIQUE (template_application_id, pack_code);

--
-- Name: template_pack template_pack_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_pack
    ADD CONSTRAINT template_pack_pkey PRIMARY KEY (id);

--
-- Name: template_pack template_pack_template_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_pack
    ADD CONSTRAINT template_pack_template_id_code_key UNIQUE (template_id, code);

--
-- Name: template_pack template_pack_template_id_code_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_pack
    ADD CONSTRAINT template_pack_template_id_code_version_key UNIQUE (template_id, code, version);

--
-- Name: template_party_alias template_party_alias_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_party_alias
    ADD CONSTRAINT template_party_alias_pkey PRIMARY KEY (id);

--
-- Name: template_party_alias template_party_alias_template_id_party_code_language_code_a_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_party_alias
    ADD CONSTRAINT template_party_alias_template_id_party_code_language_code_a_key UNIQUE (template_id, party_code, language_code, alias_text_norm);

--
-- Name: template template_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template
    ADD CONSTRAINT template_pkey PRIMARY KEY (id);

--
-- Name: template_quantity_suggestion template_quantity_suggestion_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_quantity_suggestion
    ADD CONSTRAINT template_quantity_suggestion_pkey PRIMARY KEY (id);

--
-- Name: template_quick_action template_quick_action_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_quick_action
    ADD CONSTRAINT template_quick_action_pkey PRIMARY KEY (id);

--
-- Name: template_quick_action template_quick_action_template_id_screen_position_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_quick_action
    ADD CONSTRAINT template_quick_action_template_id_screen_position_key UNIQUE (template_id, screen, "position");

--
-- Name: template_setting template_setting_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_setting
    ADD CONSTRAINT template_setting_pkey PRIMARY KEY (id);

--
-- Name: template_setting template_setting_template_id_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_setting
    ADD CONSTRAINT template_setting_template_id_key_key UNIQUE (template_id, key);

--
-- Name: template_supplier_item template_supplier_item_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_supplier_item
    ADD CONSTRAINT template_supplier_item_pkey PRIMARY KEY (id);

--
-- Name: template_supplier_item template_supplier_item_template_id_supplier_type_code_item__key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_supplier_item
    ADD CONSTRAINT template_supplier_item_template_id_supplier_type_code_item__key UNIQUE (template_id, supplier_type_code, item_code);

--
-- Name: template_supplier_type template_supplier_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_supplier_type
    ADD CONSTRAINT template_supplier_type_pkey PRIMARY KEY (id);

--
-- Name: template_supplier_type template_supplier_type_template_id_supplier_type_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_supplier_type
    ADD CONSTRAINT template_supplier_type_template_id_supplier_type_code_key UNIQUE (template_id, supplier_type_code);

--
-- Name: template_unit template_unit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_unit
    ADD CONSTRAINT template_unit_pkey PRIMARY KEY (id);

--
-- Name: template_unit template_unit_template_id_unit_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_unit
    ADD CONSTRAINT template_unit_template_id_unit_code_key UNIQUE (template_id, unit_code);

--
-- Name: transaction_line transaction_line_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_line
    ADD CONSTRAINT transaction_line_pkey PRIMARY KEY (id);

--
-- Name: transaction_line transaction_line_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_line
    ADD CONSTRAINT transaction_line_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: transaction_line transaction_line_shop_id_transaction_id_line_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_line
    ADD CONSTRAINT transaction_line_shop_id_transaction_id_line_no_key UNIQUE (shop_id, transaction_id, line_no);

--
-- Name: transaction_status transaction_status_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_status
    ADD CONSTRAINT transaction_status_code_key UNIQUE (code);

--
-- Name: transaction_status transaction_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_status
    ADD CONSTRAINT transaction_status_pkey PRIMARY KEY (id);

--
-- Name: transaction_type transaction_type_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_type
    ADD CONSTRAINT transaction_type_code_key UNIQUE (code);

--
-- Name: transaction_type transaction_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_type
    ADD CONSTRAINT transaction_type_pkey PRIMARY KEY (id);

--
-- Name: txn txn_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.txn
    ADD CONSTRAINT txn_pkey PRIMARY KEY (id);

--
-- Name: txn txn_shop_id_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.txn
    ADD CONSTRAINT txn_shop_id_id_key UNIQUE (shop_id, id);

--
-- Name: unit unit_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unit
    ADD CONSTRAINT unit_code_key UNIQUE (code);

--
-- Name: unit unit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unit
    ADD CONSTRAINT unit_pkey PRIMARY KEY (id);

--
-- Name: user_preference user_preference_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_preference
    ADD CONSTRAINT user_preference_pkey PRIMARY KEY (user_id);

--
-- Name: user_profile user_profile_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profile
    ADD CONSTRAINT user_profile_pkey PRIMARY KEY (user_id);

--
-- Name: audit_log_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_entity ON ONLY public.audit_log USING btree (shop_id, entity_type, entity_id, occurred_at DESC) WHERE (entity_id IS NOT NULL);

--
-- Name: audit_log_2026_06_shop_id_entity_type_entity_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_2026_06_shop_id_entity_type_entity_id_occurred_at_idx ON public.audit_log_2026_06 USING btree (shop_id, entity_type, entity_id, occurred_at DESC) WHERE (entity_id IS NOT NULL);

--
-- Name: audit_log_shop_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_shop_recent ON ONLY public.audit_log USING btree (shop_id, occurred_at DESC);

--
-- Name: audit_log_2026_06_shop_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_2026_06_shop_id_occurred_at_idx ON public.audit_log_2026_06 USING btree (shop_id, occurred_at DESC);

--
-- Name: audit_log_original_actor_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_original_actor_idx ON ONLY public.audit_log USING btree (shop_id, original_actor_user_id, occurred_at DESC) WHERE (original_actor_user_id IS NOT NULL);

--
-- Name: audit_log_2026_06_shop_id_original_actor_user_id_occurred_a_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_2026_06_shop_id_original_actor_user_id_occurred_a_idx ON public.audit_log_2026_06 USING btree (shop_id, original_actor_user_id, occurred_at DESC) WHERE (original_actor_user_id IS NOT NULL);

--
-- Name: audit_log_2026_07_shop_id_entity_type_entity_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_2026_07_shop_id_entity_type_entity_id_occurred_at_idx ON public.audit_log_2026_07 USING btree (shop_id, entity_type, entity_id, occurred_at DESC) WHERE (entity_id IS NOT NULL);

--
-- Name: audit_log_2026_07_shop_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_2026_07_shop_id_occurred_at_idx ON public.audit_log_2026_07 USING btree (shop_id, occurred_at DESC);

--
-- Name: audit_log_2026_07_shop_id_original_actor_user_id_occurred_a_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_2026_07_shop_id_original_actor_user_id_occurred_a_idx ON public.audit_log_2026_07 USING btree (shop_id, original_actor_user_id, occurred_at DESC) WHERE (original_actor_user_id IS NOT NULL);

--
-- Name: audit_log_2026_08_shop_id_entity_type_entity_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_2026_08_shop_id_entity_type_entity_id_occurred_at_idx ON public.audit_log_2026_08 USING btree (shop_id, entity_type, entity_id, occurred_at DESC) WHERE (entity_id IS NOT NULL);

--
-- Name: audit_log_2026_08_shop_id_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_2026_08_shop_id_occurred_at_idx ON public.audit_log_2026_08 USING btree (shop_id, occurred_at DESC);

--
-- Name: audit_log_2026_08_shop_id_original_actor_user_id_occurred_a_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_log_2026_08_shop_id_original_actor_user_id_occurred_a_idx ON public.audit_log_2026_08 USING btree (shop_id, original_actor_user_id, occurred_at DESC) WHERE (original_actor_user_id IS NOT NULL);

--
-- Name: audit_summary_shop_day; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX audit_summary_shop_day ON public.audit_summary USING btree (shop_id, day DESC);

--
-- Name: category_global_code_ux; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX category_global_code_ux ON public.category USING btree (code) WHERE (shop_id IS NULL);

--
-- Name: category_parent_sort_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX category_parent_sort_idx ON public.category USING btree (parent_id, sort_order, name);

--
-- Name: category_shop_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX category_shop_active_idx ON public.category USING btree (shop_id, is_active) WHERE (shop_id IS NOT NULL);

--
-- Name: category_shop_code_ux; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX category_shop_code_ux ON public.category USING btree (shop_id, code) WHERE (shop_id IS NOT NULL);

--
-- Name: category_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX category_updated_at_idx ON public.category USING btree (updated_at);

--
-- Name: document_shop_id_type_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_shop_id_type_created_at_idx ON public.document USING btree (shop_id, type_id, created_at DESC);

--
-- Name: document_uploaded_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX document_uploaded_by_idx ON public.document USING btree (uploaded_by, created_at DESC);

--
-- Name: expense_category_shop_id_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expense_category_shop_id_active_idx ON public.expense_category USING btree (shop_id, is_active);

--
-- Name: expense_category_shop_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expense_category_shop_updated_at_idx ON public.expense_category USING btree (shop_id, updated_at);

--
-- Name: help_channel_shop_id_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX help_channel_shop_id_active_idx ON public.help_channel USING btree (shop_id, is_active, sort_order);

--
-- Name: inventory_adjustment_line_shop_item_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_adjustment_line_shop_item_idx ON public.inventory_adjustment_line USING btree (shop_id, item_id);

--
-- Name: inventory_adjustment_shop_client_op_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX inventory_adjustment_shop_client_op_id_idx ON public.inventory_adjustment USING btree (shop_id, client_op_id) WHERE (client_op_id IS NOT NULL);

--
-- Name: inventory_adjustment_shop_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX inventory_adjustment_shop_occurred_at_idx ON public.inventory_adjustment USING btree (shop_id, occurred_at DESC);

--
-- Name: item_alias_display_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX item_alias_display_idx ON public.item_alias USING btree (item_id, language_code) WHERE is_display;

--
-- Name: item_alias_norm_prefix_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX item_alias_norm_prefix_idx ON public.item_alias USING btree (alias_text_norm text_pattern_ops) WHERE is_active;

--
-- Name: item_alias_norm_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX item_alias_norm_trgm_idx ON public.item_alias USING gin (alias_text_norm extensions.gin_trgm_ops);

--
-- Name: item_barcode_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX item_barcode_lookup_idx ON public.item_barcode USING btree (barcode) WHERE is_active;

--
-- Name: item_barcode_primary_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX item_barcode_primary_idx ON public.item_barcode USING btree (item_unit_id) WHERE (is_primary AND is_active);

--
-- Name: item_category_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX item_category_idx ON public.item USING btree (category_id) WHERE is_active;

--
-- Name: item_unit_default_receive_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX item_unit_default_receive_idx ON public.item_unit USING btree (item_id) WHERE is_default_receive;

--
-- Name: item_unit_default_sale_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX item_unit_default_sale_idx ON public.item_unit USING btree (item_id) WHERE is_default_sale;

--
-- Name: item_unit_item_sort_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX item_unit_item_sort_idx ON public.item_unit USING btree (item_id, sort_order, unit_code);

--
-- Name: item_unit_single_base_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX item_unit_single_base_idx ON public.item_unit USING btree (item_id) WHERE (conversion_to_base = (1)::numeric);

--
-- Name: location_shop_id_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX location_shop_id_active_idx ON public.location USING btree (shop_id, is_active);

--
-- Name: mutation_idempotency_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX mutation_idempotency_created_at_idx ON public.mutation_idempotency USING btree (created_at);

--
-- Name: ocr_correction_shop_id_document_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ocr_correction_shop_id_document_id_idx ON public.ocr_correction USING btree (shop_id, document_id);

--
-- Name: ocr_job_status_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ocr_job_status_created_at_idx ON public.ocr_job USING btree (status, created_at);

--
-- Name: organization_membership_organization_id_role_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organization_membership_organization_id_role_id_idx ON public.organization_membership USING btree (organization_id, role_id) WHERE is_active;

--
-- Name: organization_membership_user_id_organization_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX organization_membership_user_id_organization_id_idx ON public.organization_membership USING btree (user_id, organization_id) WHERE is_active;

--
-- Name: party_alias_norm_prefix_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_alias_norm_prefix_idx ON public.party_alias USING btree (shop_id, alias_text_norm text_pattern_ops);

--
-- Name: party_alias_norm_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_alias_norm_trgm_idx ON public.party_alias USING gin (alias_text_norm extensions.gin_trgm_ops);

--
-- Name: party_shop_id_type_id_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_shop_id_type_id_active_idx ON public.party USING btree (shop_id, type_id, is_active);

--
-- Name: party_shop_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX party_shop_updated_at_idx ON public.party USING btree (shop_id, updated_at);

--
-- Name: payment_allocation_shop_transaction_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payment_allocation_shop_transaction_idx ON public.payment_allocation USING btree (shop_id, transaction_id);

--
-- Name: payment_refund_of_transaction_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payment_refund_of_transaction_idx ON public.payment USING btree (shop_id, refund_of_transaction_id) WHERE (refund_of_transaction_id IS NOT NULL);

--
-- Name: payment_shop_client_op_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX payment_shop_client_op_id_idx ON public.payment USING btree (shop_id, client_op_id) WHERE (client_op_id IS NOT NULL);

--
-- Name: payment_shop_party_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payment_shop_party_occurred_at_idx ON public.payment USING btree (shop_id, party_id, occurred_at DESC);

--
-- Name: platform_config_default_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX platform_config_default_uq ON public.platform_config USING btree (key) WHERE (org_id IS NULL);

--
-- Name: platform_config_org_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_config_org_idx ON public.platform_config USING btree (org_id);

--
-- Name: platform_config_org_key_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX platform_config_org_key_uq ON public.platform_config USING btree (org_id, key) WHERE (org_id IS NOT NULL);

--
-- Name: platform_membership_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX platform_membership_user_id_idx ON public.platform_membership USING btree (user_id) WHERE is_active;

--
-- Name: shop_invite_email_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_invite_email_pending_idx ON public.shop_invite USING btree (email) WHERE ((accepted_at IS NULL) AND (email IS NOT NULL));

--
-- Name: shop_invite_pending_email_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shop_invite_pending_email_unique ON public.shop_invite USING btree (shop_id, email) WHERE ((accepted_at IS NULL) AND (email IS NOT NULL));

--
-- Name: shop_invite_pending_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shop_invite_pending_unique ON public.shop_invite USING btree (shop_id, phone) WHERE (accepted_at IS NULL);

--
-- Name: shop_invite_phone_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_invite_phone_pending_idx ON public.shop_invite USING btree (phone) WHERE (accepted_at IS NULL);

--
-- Name: shop_item_alias_display_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shop_item_alias_display_idx ON public.shop_item_alias USING btree (shop_id, shop_item_id, language_code) WHERE is_display;

--
-- Name: shop_item_alias_norm_prefix_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_alias_norm_prefix_idx ON public.shop_item_alias USING btree (shop_id, alias_text_norm text_pattern_ops) WHERE is_active;

--
-- Name: shop_item_alias_norm_trgm_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_alias_norm_trgm_idx ON public.shop_item_alias USING gin (alias_text_norm extensions.gin_trgm_ops);

--
-- Name: shop_item_alias_shop_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_alias_shop_updated_at_idx ON public.shop_item_alias USING btree (shop_id, updated_at);

--
-- Name: shop_item_barcode_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_barcode_lookup_idx ON public.shop_item_barcode USING btree (shop_id, barcode) WHERE is_active;

--
-- Name: shop_item_barcode_primary_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shop_item_barcode_primary_idx ON public.shop_item_barcode USING btree (shop_id, shop_item_unit_id) WHERE (is_primary AND is_active);

--
-- Name: shop_item_barcode_shop_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_barcode_shop_updated_at_idx ON public.shop_item_barcode USING btree (shop_id, updated_at);

--
-- Name: shop_item_category_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_category_idx ON public.shop_item USING btree (shop_id, category_id);

--
-- Name: shop_item_item_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_item_id_idx ON public.shop_item USING btree (item_id) WHERE (item_id IS NOT NULL);

--
-- Name: shop_item_shop_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_shop_active_idx ON public.shop_item USING btree (shop_id, is_active);

--
-- Name: shop_item_shop_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_shop_updated_at_idx ON public.shop_item USING btree (shop_id, updated_at);

--
-- Name: shop_item_unit_activation_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shop_item_unit_activation_idx ON public.shop_item_unit USING btree (shop_id, shop_item_id, item_unit_id) WHERE (item_unit_id IS NOT NULL);

--
-- Name: shop_item_unit_base_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shop_item_unit_base_idx ON public.shop_item_unit USING btree (shop_id, shop_item_id) WHERE (conversion_to_base = (1)::numeric);

--
-- Name: shop_item_unit_default_receive_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shop_item_unit_default_receive_idx ON public.shop_item_unit USING btree (shop_id, shop_item_id) WHERE is_default_receive;

--
-- Name: shop_item_unit_default_sale_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX shop_item_unit_default_sale_idx ON public.shop_item_unit USING btree (shop_id, shop_item_id) WHERE is_default_sale;

--
-- Name: shop_item_unit_shop_item_sort_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_unit_shop_item_sort_idx ON public.shop_item_unit USING btree (shop_id, shop_item_id, sort_order, unit_code);

--
-- Name: shop_item_unit_shop_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_unit_shop_updated_at_idx ON public.shop_item_unit USING btree (shop_id, updated_at);

--
-- Name: shop_item_usage_shop_rank_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_item_usage_shop_rank_idx ON public.shop_item_usage USING btree (shop_id, sale_count DESC, last_sale_at DESC);

--
-- Name: shop_membership_shop_id_role_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_membership_shop_id_role_id_idx ON public.shop_membership USING btree (shop_id, role_id) WHERE is_active;

--
-- Name: shop_membership_user_id_shop_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_membership_user_id_shop_id_idx ON public.shop_membership USING btree (user_id, shop_id) WHERE is_active;

--
-- Name: shop_organization_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_organization_id_idx ON public.shop USING btree (organization_id);

--
-- Name: shop_party_usage_shop_recent_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_party_usage_shop_recent_idx ON public.shop_party_usage USING btree (shop_id, GREATEST(COALESCE(last_sale_at, '-infinity'::timestamp with time zone), COALESCE(last_receive_at, '-infinity'::timestamp with time zone), COALESCE(last_payment_at, '-infinity'::timestamp with time zone)) DESC);

--
-- Name: shop_setting_shop_id_key_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_setting_shop_id_key_idx ON public.shop_setting USING btree (shop_id, key);

--
-- Name: shop_suggestion_read_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_suggestion_read_idx ON public.shop_suggestion USING btree (shop_id, screen, context_key, rank) WHERE is_active;

--
-- Name: shop_supplier_item_profile_shop_supplier_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_supplier_item_profile_shop_supplier_idx ON public.shop_supplier_item_profile USING btree (shop_id, supplier_id, receive_count DESC, last_received_at DESC);

--
-- Name: shop_sync_audit_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX shop_sync_audit_lookup_idx ON public.shop_sync_audit USING btree (shop_id, user_id, kind, ran_at DESC);

--
-- Name: stock_movement_adjustment_line_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX stock_movement_adjustment_line_idx ON public.stock_movement USING btree (shop_id, inventory_adjustment_line_id) WHERE (inventory_adjustment_line_id IS NOT NULL);

--
-- Name: stock_movement_shop_item_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX stock_movement_shop_item_occurred_at_idx ON public.stock_movement USING btree (shop_id, item_id, occurred_at DESC);

--
-- Name: stock_movement_transaction_line_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX stock_movement_transaction_line_idx ON public.stock_movement USING btree (shop_id, transaction_line_id) WHERE (transaction_line_id IS NOT NULL);

--
-- Name: supplier_item_unit_cost_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX supplier_item_unit_cost_lookup_idx ON public.supplier_item_unit_cost USING btree (shop_id, shop_item_unit_id, last_received_at DESC);

--
-- Name: supplier_type_shop_id_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX supplier_type_shop_id_active_idx ON public.supplier_type USING btree (shop_id, is_active, sort_order);

--
-- Name: template_application_shop_id_applied_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX template_application_shop_id_applied_at_idx ON public.template_application USING btree (shop_id, applied_at DESC);

--
-- Name: template_item_alias_display_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX template_item_alias_display_idx ON public.template_item_alias USING btree (template_id, item_code, language_code) WHERE is_display;

--
-- Name: template_item_template_id_sort_order_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX template_item_template_id_sort_order_idx ON public.template_item USING btree (template_id, sort_order);

--
-- Name: template_quantity_suggestion_template_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX template_quantity_suggestion_template_context_idx ON public.template_quantity_suggestion USING btree (template_id, context, sort_order);

--
-- Name: transaction_line_shop_item_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transaction_line_shop_item_idx ON public.transaction_line USING btree (shop_id, item_id);

--
-- Name: transaction_line_shop_item_unit_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transaction_line_shop_item_unit_idx ON public.transaction_line USING btree (shop_id, shop_item_unit_id) WHERE (shop_item_unit_id IS NOT NULL);

--
-- Name: transaction_line_shop_transaction_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX transaction_line_shop_transaction_idx ON public.transaction_line USING btree (shop_id, transaction_id, line_no);

--
-- Name: txn_shop_client_op_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX txn_shop_client_op_id_idx ON public.txn USING btree (shop_id, client_op_id) WHERE (client_op_id IS NOT NULL);

--
-- Name: txn_shop_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX txn_shop_created_at_idx ON public.txn USING btree (shop_id, created_at DESC);

--
-- Name: txn_shop_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX txn_shop_occurred_at_idx ON public.txn USING btree (shop_id, occurred_at DESC);

--
-- Name: txn_shop_party_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX txn_shop_party_occurred_at_idx ON public.txn USING btree (shop_id, party_id, occurred_at DESC);

--
-- Name: txn_shop_type_status_occurred_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX txn_shop_type_status_occurred_at_idx ON public.txn USING btree (shop_id, type_id, status_id, occurred_at DESC);

--
-- Name: unit_updated_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX unit_updated_at_idx ON public.unit USING btree (updated_at);

--
-- Name: audit_log_2026_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_pkey ATTACH PARTITION public.audit_log_2026_06_pkey;

--
-- Name: audit_log_2026_06_shop_id_entity_type_entity_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_entity ATTACH PARTITION public.audit_log_2026_06_shop_id_entity_type_entity_id_occurred_at_idx;

--
-- Name: audit_log_2026_06_shop_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_shop_recent ATTACH PARTITION public.audit_log_2026_06_shop_id_occurred_at_idx;

--
-- Name: audit_log_2026_06_shop_id_original_actor_user_id_occurred_a_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_original_actor_idx ATTACH PARTITION public.audit_log_2026_06_shop_id_original_actor_user_id_occurred_a_idx;

--
-- Name: audit_log_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_pkey ATTACH PARTITION public.audit_log_2026_07_pkey;

--
-- Name: audit_log_2026_07_shop_id_entity_type_entity_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_entity ATTACH PARTITION public.audit_log_2026_07_shop_id_entity_type_entity_id_occurred_at_idx;

--
-- Name: audit_log_2026_07_shop_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_shop_recent ATTACH PARTITION public.audit_log_2026_07_shop_id_occurred_at_idx;

--
-- Name: audit_log_2026_07_shop_id_original_actor_user_id_occurred_a_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_original_actor_idx ATTACH PARTITION public.audit_log_2026_07_shop_id_original_actor_user_id_occurred_a_idx;

--
-- Name: audit_log_2026_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_pkey ATTACH PARTITION public.audit_log_2026_08_pkey;

--
-- Name: audit_log_2026_08_shop_id_entity_type_entity_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_entity ATTACH PARTITION public.audit_log_2026_08_shop_id_entity_type_entity_id_occurred_at_idx;

--
-- Name: audit_log_2026_08_shop_id_occurred_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_shop_recent ATTACH PARTITION public.audit_log_2026_08_shop_id_occurred_at_idx;

--
-- Name: audit_log_2026_08_shop_id_original_actor_user_id_occurred_a_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.audit_log_original_actor_idx ATTACH PARTITION public.audit_log_2026_08_shop_id_original_actor_user_id_occurred_a_idx;

--
-- Name: audit_log audit_log_action_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.audit_log
    ADD CONSTRAINT audit_log_action_code_fkey FOREIGN KEY (action_code) REFERENCES public.audit_action_code(code) ON DELETE RESTRICT;

--
-- Name: audit_log audit_log_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.audit_log
    ADD CONSTRAINT audit_log_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: audit_log audit_log_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public.audit_log
    ADD CONSTRAINT audit_log_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: audit_summary audit_summary_action_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_summary
    ADD CONSTRAINT audit_summary_action_code_fkey FOREIGN KEY (action_code) REFERENCES public.audit_action_code(code) ON DELETE RESTRICT;

--
-- Name: audit_summary audit_summary_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_summary
    ADD CONSTRAINT audit_summary_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: category category_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.category
    ADD CONSTRAINT category_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: category category_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.category
    ADD CONSTRAINT category_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.category(id) ON DELETE RESTRICT;

--
-- Name: category category_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.category
    ADD CONSTRAINT category_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: document document_ocr_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_ocr_status_id_fkey FOREIGN KEY (ocr_status_id) REFERENCES public.ocr_status(id) ON DELETE RESTRICT;

--
-- Name: document document_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: document document_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_type_id_fkey FOREIGN KEY (type_id) REFERENCES public.document_type(id) ON DELETE RESTRICT;

--
-- Name: document document_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT document_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

--
-- Name: expense_category expense_category_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_category
    ADD CONSTRAINT expense_category_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: expense_category expense_category_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.expense_category
    ADD CONSTRAINT expense_category_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: help_channel help_channel_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_channel
    ADD CONSTRAINT help_channel_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: help_channel help_channel_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.help_channel
    ADD CONSTRAINT help_channel_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: inventory_adjustment inventory_adjustment_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment
    ADD CONSTRAINT inventory_adjustment_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

--
-- Name: inventory_adjustment inventory_adjustment_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment
    ADD CONSTRAINT inventory_adjustment_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

--
-- Name: inventory_adjustment_line inventory_adjustment_line_shop_id_adjustment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment_line
    ADD CONSTRAINT inventory_adjustment_line_shop_id_adjustment_id_fkey FOREIGN KEY (shop_id, adjustment_id) REFERENCES public.inventory_adjustment(shop_id, id) ON DELETE CASCADE;

--
-- Name: inventory_adjustment_line inventory_adjustment_line_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment_line
    ADD CONSTRAINT inventory_adjustment_line_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: inventory_adjustment_line inventory_adjustment_line_shop_id_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment_line
    ADD CONSTRAINT inventory_adjustment_line_shop_id_item_id_fkey FOREIGN KEY (shop_id, item_id) REFERENCES public.shop_item(shop_id, id) ON DELETE RESTRICT;

--
-- Name: inventory_adjustment inventory_adjustment_reason_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment
    ADD CONSTRAINT inventory_adjustment_reason_id_fkey FOREIGN KEY (reason_id) REFERENCES public.adjustment_reason(id) ON DELETE RESTRICT;

--
-- Name: inventory_adjustment inventory_adjustment_shop_id_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment
    ADD CONSTRAINT inventory_adjustment_shop_id_document_id_fkey FOREIGN KEY (shop_id, document_id) REFERENCES public.document(shop_id, id) ON DELETE RESTRICT;

--
-- Name: inventory_adjustment inventory_adjustment_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment
    ADD CONSTRAINT inventory_adjustment_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: inventory_adjustment inventory_adjustment_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventory_adjustment
    ADD CONSTRAINT inventory_adjustment_status_id_fkey FOREIGN KEY (status_id) REFERENCES public.transaction_status(id) ON DELETE RESTRICT;

--
-- Name: item_alias item_alias_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_alias
    ADD CONSTRAINT item_alias_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.item(id) ON DELETE CASCADE;

--
-- Name: item_alias item_alias_language_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_alias
    ADD CONSTRAINT item_alias_language_code_fkey FOREIGN KEY (language_code) REFERENCES public.language(code) ON DELETE RESTRICT;

--
-- Name: item_barcode item_barcode_item_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_barcode
    ADD CONSTRAINT item_barcode_item_unit_id_fkey FOREIGN KEY (item_unit_id) REFERENCES public.item_unit(id) ON DELETE CASCADE;

--
-- Name: item item_base_unit_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item
    ADD CONSTRAINT item_base_unit_code_fkey FOREIGN KEY (base_unit_code) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: item item_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item
    ADD CONSTRAINT item_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.category(id) ON DELETE RESTRICT;

--
-- Name: item_unit item_unit_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_unit
    ADD CONSTRAINT item_unit_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.item(id) ON DELETE CASCADE;

--
-- Name: item_unit item_unit_unit_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.item_unit
    ADD CONSTRAINT item_unit_unit_code_fkey FOREIGN KEY (unit_code) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: location location_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: location location_kind_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_kind_id_fkey FOREIGN KEY (kind_id) REFERENCES public.location_kind(id) ON DELETE RESTRICT;

--
-- Name: location location_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.location
    ADD CONSTRAINT location_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: mutation_idempotency mutation_idempotency_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mutation_idempotency
    ADD CONSTRAINT mutation_idempotency_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: ocr_correction ocr_correction_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_correction
    ADD CONSTRAINT ocr_correction_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

--
-- Name: ocr_correction ocr_correction_shop_id_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_correction
    ADD CONSTRAINT ocr_correction_shop_id_document_id_fkey FOREIGN KEY (shop_id, document_id) REFERENCES public.document(shop_id, id) ON DELETE CASCADE;

--
-- Name: ocr_job ocr_job_shop_id_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_job
    ADD CONSTRAINT ocr_job_shop_id_document_id_fkey FOREIGN KEY (shop_id, document_id) REFERENCES public.document(shop_id, id) ON DELETE CASCADE;

--
-- Name: organization organization_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT organization_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: organization_membership organization_membership_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_membership
    ADD CONSTRAINT organization_membership_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;

--
-- Name: organization_membership organization_membership_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_membership
    ADD CONSTRAINT organization_membership_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.organization_role(id) ON DELETE RESTRICT;

--
-- Name: organization_membership organization_membership_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_membership
    ADD CONSTRAINT organization_membership_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

--
-- Name: organization_role_capability organization_role_capability_capability_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_role_capability
    ADD CONSTRAINT organization_role_capability_capability_code_fkey FOREIGN KEY (capability_code) REFERENCES public.capability(code) ON DELETE CASCADE;

--
-- Name: organization_role_capability organization_role_capability_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_role_capability
    ADD CONSTRAINT organization_role_capability_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.organization_role(id) ON DELETE CASCADE;

--
-- Name: party_alias party_alias_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_alias
    ADD CONSTRAINT party_alias_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: party_alias party_alias_language_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_alias
    ADD CONSTRAINT party_alias_language_code_fkey FOREIGN KEY (language_code) REFERENCES public.language(code) ON DELETE RESTRICT;

--
-- Name: party_alias party_alias_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_alias
    ADD CONSTRAINT party_alias_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: party_alias party_alias_shop_id_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party_alias
    ADD CONSTRAINT party_alias_shop_id_party_id_fkey FOREIGN KEY (shop_id, party_id) REFERENCES public.party(shop_id, id) ON DELETE CASCADE;

--
-- Name: party party_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party
    ADD CONSTRAINT party_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: party party_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party
    ADD CONSTRAINT party_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: party party_shop_id_supplier_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party
    ADD CONSTRAINT party_shop_id_supplier_type_id_fkey FOREIGN KEY (shop_id, supplier_type_id) REFERENCES public.supplier_type(shop_id, id) ON DELETE SET NULL;

--
-- Name: party party_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.party
    ADD CONSTRAINT party_type_id_fkey FOREIGN KEY (type_id) REFERENCES public.party_type(id) ON DELETE RESTRICT;

--
-- Name: payment_allocation payment_allocation_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocation
    ADD CONSTRAINT payment_allocation_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: payment_allocation payment_allocation_shop_id_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocation
    ADD CONSTRAINT payment_allocation_shop_id_payment_id_fkey FOREIGN KEY (shop_id, payment_id) REFERENCES public.payment(shop_id, id) ON DELETE CASCADE;

--
-- Name: payment_allocation payment_allocation_shop_id_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_allocation
    ADD CONSTRAINT payment_allocation_shop_id_transaction_id_fkey FOREIGN KEY (shop_id, transaction_id) REFERENCES public.txn(shop_id, id) ON DELETE RESTRICT;

--
-- Name: payment payment_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

--
-- Name: payment payment_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_method_id_fkey FOREIGN KEY (method_id) REFERENCES public.payment_method(id) ON DELETE RESTRICT;

--
-- Name: payment payment_shop_id_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_shop_id_document_id_fkey FOREIGN KEY (shop_id, document_id) REFERENCES public.document(shop_id, id) ON DELETE RESTRICT;

--
-- Name: payment payment_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: payment payment_shop_id_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_shop_id_party_id_fkey FOREIGN KEY (shop_id, party_id) REFERENCES public.party(shop_id, id) ON DELETE RESTRICT;

--
-- Name: payment payment_shop_id_refund_of_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_shop_id_refund_of_transaction_id_fkey FOREIGN KEY (shop_id, refund_of_transaction_id) REFERENCES public.txn(shop_id, id) ON DELETE RESTRICT;

--
-- Name: platform_config platform_config_org_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_config
    ADD CONSTRAINT platform_config_org_id_fkey FOREIGN KEY (org_id) REFERENCES public.organization(id) ON DELETE CASCADE;

--
-- Name: platform_config platform_config_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_config
    ADD CONSTRAINT platform_config_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);

--
-- Name: platform_membership platform_membership_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_membership
    ADD CONSTRAINT platform_membership_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

--
-- Name: shop shop_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop
    ADD CONSTRAINT shop_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: shop shop_currency_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop
    ADD CONSTRAINT shop_currency_code_fkey FOREIGN KEY (currency_code) REFERENCES public.currency(code) ON DELETE RESTRICT;

--
-- Name: shop shop_default_language_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop
    ADD CONSTRAINT shop_default_language_code_fkey FOREIGN KEY (default_language_code) REFERENCES public.language(code) ON DELETE RESTRICT;

--
-- Name: shop_invite shop_invite_accepted_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_invite
    ADD CONSTRAINT shop_invite_accepted_by_user_id_fkey FOREIGN KEY (accepted_by_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: shop_invite shop_invite_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_invite
    ADD CONSTRAINT shop_invite_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

--
-- Name: shop_invite shop_invite_role_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_invite
    ADD CONSTRAINT shop_invite_role_code_fkey FOREIGN KEY (role_code) REFERENCES public.shop_role(code) ON DELETE RESTRICT;

--
-- Name: shop_invite shop_invite_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_invite
    ADD CONSTRAINT shop_invite_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_item_alias shop_item_alias_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_alias
    ADD CONSTRAINT shop_item_alias_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: shop_item_alias shop_item_alias_language_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_alias
    ADD CONSTRAINT shop_item_alias_language_code_fkey FOREIGN KEY (language_code) REFERENCES public.language(code) ON DELETE RESTRICT;

--
-- Name: shop_item_alias shop_item_alias_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_alias
    ADD CONSTRAINT shop_item_alias_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_item_alias shop_item_alias_shop_id_shop_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_alias
    ADD CONSTRAINT shop_item_alias_shop_id_shop_item_id_fkey FOREIGN KEY (shop_id, shop_item_id) REFERENCES public.shop_item(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_item_barcode shop_item_barcode_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_barcode
    ADD CONSTRAINT shop_item_barcode_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: shop_item_barcode shop_item_barcode_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_barcode
    ADD CONSTRAINT shop_item_barcode_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_item_barcode shop_item_barcode_shop_id_shop_item_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_barcode
    ADD CONSTRAINT shop_item_barcode_shop_id_shop_item_unit_id_fkey FOREIGN KEY (shop_id, shop_item_unit_id) REFERENCES public.shop_item_unit(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_item shop_item_base_unit_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item
    ADD CONSTRAINT shop_item_base_unit_code_fkey FOREIGN KEY (base_unit_code) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: shop_item shop_item_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item
    ADD CONSTRAINT shop_item_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.category(id) ON DELETE RESTRICT;

--
-- Name: shop_item shop_item_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item
    ADD CONSTRAINT shop_item_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: shop_item_entry_profile shop_item_entry_profile_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_entry_profile
    ADD CONSTRAINT shop_item_entry_profile_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_item_entry_profile shop_item_entry_profile_shop_id_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_entry_profile
    ADD CONSTRAINT shop_item_entry_profile_shop_id_item_id_fkey FOREIGN KEY (shop_id, item_id) REFERENCES public.shop_item(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_item_entry_profile shop_item_entry_profile_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_entry_profile
    ADD CONSTRAINT shop_item_entry_profile_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unit(id) ON DELETE RESTRICT;

--
-- Name: shop_item shop_item_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item
    ADD CONSTRAINT shop_item_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.item(id) ON DELETE RESTRICT;

--
-- Name: shop_item shop_item_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item
    ADD CONSTRAINT shop_item_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_item_unit shop_item_unit_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_unit
    ADD CONSTRAINT shop_item_unit_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: shop_item_unit shop_item_unit_item_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_unit
    ADD CONSTRAINT shop_item_unit_item_unit_id_fkey FOREIGN KEY (item_unit_id) REFERENCES public.item_unit(id) ON DELETE RESTRICT;

--
-- Name: shop_item_unit shop_item_unit_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_unit
    ADD CONSTRAINT shop_item_unit_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_item_unit shop_item_unit_shop_id_shop_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_unit
    ADD CONSTRAINT shop_item_unit_shop_id_shop_item_id_fkey FOREIGN KEY (shop_id, shop_item_id) REFERENCES public.shop_item(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_item_unit shop_item_unit_unit_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_unit
    ADD CONSTRAINT shop_item_unit_unit_code_fkey FOREIGN KEY (unit_code) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: shop_item_usage shop_item_usage_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_usage
    ADD CONSTRAINT shop_item_usage_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_item_usage shop_item_usage_shop_id_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_item_usage
    ADD CONSTRAINT shop_item_usage_shop_id_item_id_fkey FOREIGN KEY (shop_id, item_id) REFERENCES public.shop_item(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_membership shop_membership_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_membership
    ADD CONSTRAINT shop_membership_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.shop_role(id) ON DELETE RESTRICT;

--
-- Name: shop_membership shop_membership_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_membership
    ADD CONSTRAINT shop_membership_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_membership shop_membership_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_membership
    ADD CONSTRAINT shop_membership_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

--
-- Name: shop shop_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop
    ADD CONSTRAINT shop_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE RESTRICT;

--
-- Name: shop_party_usage shop_party_usage_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_party_usage
    ADD CONSTRAINT shop_party_usage_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_party_usage shop_party_usage_shop_id_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_party_usage
    ADD CONSTRAINT shop_party_usage_shop_id_party_id_fkey FOREIGN KEY (shop_id, party_id) REFERENCES public.party(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_role_capability shop_role_capability_capability_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_role_capability
    ADD CONSTRAINT shop_role_capability_capability_code_fkey FOREIGN KEY (capability_code) REFERENCES public.capability(code) ON DELETE CASCADE;

--
-- Name: shop_role_capability shop_role_capability_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_role_capability
    ADD CONSTRAINT shop_role_capability_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.shop_role(id) ON DELETE CASCADE;

--
-- Name: shop_setting shop_setting_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_setting
    ADD CONSTRAINT shop_setting_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: shop_setting shop_setting_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_setting
    ADD CONSTRAINT shop_setting_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_suggestion shop_suggestion_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_suggestion
    ADD CONSTRAINT shop_suggestion_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES public.payment_method(id) ON DELETE RESTRICT;

--
-- Name: shop_suggestion shop_suggestion_shop_id_expense_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_suggestion
    ADD CONSTRAINT shop_suggestion_shop_id_expense_category_id_fkey FOREIGN KEY (shop_id, expense_category_id) REFERENCES public.expense_category(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_suggestion shop_suggestion_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_suggestion
    ADD CONSTRAINT shop_suggestion_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_suggestion shop_suggestion_shop_id_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_suggestion
    ADD CONSTRAINT shop_suggestion_shop_id_item_id_fkey FOREIGN KEY (shop_id, item_id) REFERENCES public.shop_item(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_suggestion shop_suggestion_shop_id_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_suggestion
    ADD CONSTRAINT shop_suggestion_shop_id_party_id_fkey FOREIGN KEY (shop_id, party_id) REFERENCES public.party(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_suggestion shop_suggestion_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_suggestion
    ADD CONSTRAINT shop_suggestion_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unit(id) ON DELETE RESTRICT;

--
-- Name: shop_supplier_item_profile shop_supplier_item_profile_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_supplier_item_profile
    ADD CONSTRAINT shop_supplier_item_profile_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_supplier_item_profile shop_supplier_item_profile_shop_id_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_supplier_item_profile
    ADD CONSTRAINT shop_supplier_item_profile_shop_id_item_id_fkey FOREIGN KEY (shop_id, item_id) REFERENCES public.shop_item(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_supplier_item_profile shop_supplier_item_profile_shop_id_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_supplier_item_profile
    ADD CONSTRAINT shop_supplier_item_profile_shop_id_supplier_id_fkey FOREIGN KEY (shop_id, supplier_id) REFERENCES public.party(shop_id, id) ON DELETE CASCADE;

--
-- Name: shop_supplier_item_profile shop_supplier_item_profile_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_supplier_item_profile
    ADD CONSTRAINT shop_supplier_item_profile_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unit(id) ON DELETE RESTRICT;

--
-- Name: shop_sync_audit shop_sync_audit_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_sync_audit
    ADD CONSTRAINT shop_sync_audit_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: shop_sync_audit shop_sync_audit_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shop_sync_audit
    ADD CONSTRAINT shop_sync_audit_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

--
-- Name: stock_movement stock_movement_adjustment_line_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movement
    ADD CONSTRAINT stock_movement_adjustment_line_fk FOREIGN KEY (shop_id, inventory_adjustment_line_id) REFERENCES public.inventory_adjustment_line(shop_id, id) ON DELETE CASCADE;

--
-- Name: stock_movement stock_movement_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movement
    ADD CONSTRAINT stock_movement_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: stock_movement stock_movement_shop_id_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movement
    ADD CONSTRAINT stock_movement_shop_id_item_id_fkey FOREIGN KEY (shop_id, item_id) REFERENCES public.shop_item(shop_id, id) ON DELETE RESTRICT;

--
-- Name: stock_movement stock_movement_shop_id_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movement
    ADD CONSTRAINT stock_movement_shop_id_location_id_fkey FOREIGN KEY (shop_id, location_id) REFERENCES public.location(shop_id, id) ON DELETE RESTRICT;

--
-- Name: stock_movement stock_movement_shop_id_transaction_line_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stock_movement
    ADD CONSTRAINT stock_movement_shop_id_transaction_line_id_fkey FOREIGN KEY (shop_id, transaction_line_id) REFERENCES public.transaction_line(shop_id, id) ON DELETE CASCADE;

--
-- Name: supplier_item_unit_cost supplier_item_unit_cost_party_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_item_unit_cost
    ADD CONSTRAINT supplier_item_unit_cost_party_fk FOREIGN KEY (shop_id, party_id) REFERENCES public.party(shop_id, id) ON DELETE CASCADE;

--
-- Name: supplier_item_unit_cost supplier_item_unit_cost_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_item_unit_cost
    ADD CONSTRAINT supplier_item_unit_cost_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: supplier_item_unit_cost supplier_item_unit_cost_shop_id_shop_item_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_item_unit_cost
    ADD CONSTRAINT supplier_item_unit_cost_shop_id_shop_item_unit_id_fkey FOREIGN KEY (shop_id, shop_item_unit_id) REFERENCES public.shop_item_unit(shop_id, id) ON DELETE CASCADE;

--
-- Name: supplier_type supplier_type_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_type
    ADD CONSTRAINT supplier_type_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: supplier_type supplier_type_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supplier_type
    ADD CONSTRAINT supplier_type_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: template_application template_application_applied_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_application
    ADD CONSTRAINT template_application_applied_by_fkey FOREIGN KEY (applied_by) REFERENCES auth.users(id) ON DELETE SET NULL;

--
-- Name: template_application template_application_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_application
    ADD CONSTRAINT template_application_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: template_application template_application_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_application
    ADD CONSTRAINT template_application_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.template(id) ON DELETE RESTRICT;

--
-- Name: template_application template_application_template_id_template_version_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_application
    ADD CONSTRAINT template_application_template_id_template_version_fkey FOREIGN KEY (template_id, template_version) REFERENCES public.template(id, version) ON DELETE RESTRICT;

--
-- Name: template template_currency_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template
    ADD CONSTRAINT template_currency_default_fkey FOREIGN KEY (currency_default) REFERENCES public.currency(code) ON DELETE RESTRICT;

--
-- Name: template_expense_category template_expense_category_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_expense_category
    ADD CONSTRAINT template_expense_category_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.template(id) ON DELETE CASCADE;

--
-- Name: template_item_alias template_item_alias_language_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item_alias
    ADD CONSTRAINT template_item_alias_language_code_fkey FOREIGN KEY (language_code) REFERENCES public.language(code) ON DELETE RESTRICT;

--
-- Name: template_item_alias template_item_alias_template_id_item_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item_alias
    ADD CONSTRAINT template_item_alias_template_id_item_code_fkey FOREIGN KEY (template_id, item_code) REFERENCES public.template_item(template_id, item_code) ON DELETE CASCADE;

--
-- Name: template_item template_item_base_unit_code_override_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item
    ADD CONSTRAINT template_item_base_unit_code_override_fkey FOREIGN KEY (base_unit_code_override) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: template_item template_item_default_receive_unit_code_override_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item
    ADD CONSTRAINT template_item_default_receive_unit_code_override_fkey FOREIGN KEY (default_receive_unit_code_override) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: template_item template_item_default_sale_unit_code_override_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item
    ADD CONSTRAINT template_item_default_sale_unit_code_override_fkey FOREIGN KEY (default_sale_unit_code_override) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: template_item template_item_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item
    ADD CONSTRAINT template_item_item_id_fkey FOREIGN KEY (item_id) REFERENCES public.item(id) ON DELETE RESTRICT;

--
-- Name: template_item template_item_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item
    ADD CONSTRAINT template_item_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.template(id) ON DELETE CASCADE;

--
-- Name: template_item_unit template_item_unit_template_id_item_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item_unit
    ADD CONSTRAINT template_item_unit_template_id_item_code_fkey FOREIGN KEY (template_id, item_code) REFERENCES public.template_item(template_id, item_code) ON DELETE CASCADE;

--
-- Name: template_item_unit template_item_unit_unit_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_item_unit
    ADD CONSTRAINT template_item_unit_unit_code_fkey FOREIGN KEY (unit_code) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: template template_locale_default_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template
    ADD CONSTRAINT template_locale_default_fkey FOREIGN KEY (locale_default) REFERENCES public.language(code) ON DELETE RESTRICT;

--
-- Name: template_pack_application template_pack_application_shop_id_template_application_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_pack_application
    ADD CONSTRAINT template_pack_application_shop_id_template_application_id_fkey FOREIGN KEY (shop_id, template_application_id) REFERENCES public.template_application(shop_id, id) ON DELETE CASCADE;

--
-- Name: template_pack template_pack_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_pack
    ADD CONSTRAINT template_pack_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.template(id) ON DELETE CASCADE;

--
-- Name: template_party_alias template_party_alias_language_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_party_alias
    ADD CONSTRAINT template_party_alias_language_code_fkey FOREIGN KEY (language_code) REFERENCES public.language(code) ON DELETE RESTRICT;

--
-- Name: template_party_alias template_party_alias_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_party_alias
    ADD CONSTRAINT template_party_alias_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.template(id) ON DELETE CASCADE;

--
-- Name: template_quantity_suggestion template_quantity_suggestion_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_quantity_suggestion
    ADD CONSTRAINT template_quantity_suggestion_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.template(id) ON DELETE CASCADE;

--
-- Name: template_quantity_suggestion template_quantity_suggestion_unit_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_quantity_suggestion
    ADD CONSTRAINT template_quantity_suggestion_unit_code_fkey FOREIGN KEY (unit_code) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: template_quick_action template_quick_action_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_quick_action
    ADD CONSTRAINT template_quick_action_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.template(id) ON DELETE CASCADE;

--
-- Name: template_setting template_setting_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_setting
    ADD CONSTRAINT template_setting_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.template(id) ON DELETE CASCADE;

--
-- Name: template_supplier_item template_supplier_item_template_id_item_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_supplier_item
    ADD CONSTRAINT template_supplier_item_template_id_item_code_fkey FOREIGN KEY (template_id, item_code) REFERENCES public.template_item(template_id, item_code) ON DELETE CASCADE;

--
-- Name: template_supplier_item template_supplier_item_template_id_supplier_type_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_supplier_item
    ADD CONSTRAINT template_supplier_item_template_id_supplier_type_code_fkey FOREIGN KEY (template_id, supplier_type_code) REFERENCES public.template_supplier_type(template_id, supplier_type_code) ON DELETE CASCADE;

--
-- Name: template_supplier_item template_supplier_item_usual_unit_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_supplier_item
    ADD CONSTRAINT template_supplier_item_usual_unit_code_fkey FOREIGN KEY (usual_unit_code) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: template_supplier_type template_supplier_type_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_supplier_type
    ADD CONSTRAINT template_supplier_type_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.template(id) ON DELETE CASCADE;

--
-- Name: template_unit template_unit_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_unit
    ADD CONSTRAINT template_unit_template_id_fkey FOREIGN KEY (template_id) REFERENCES public.template(id) ON DELETE CASCADE;

--
-- Name: template_unit template_unit_unit_code_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.template_unit
    ADD CONSTRAINT template_unit_unit_code_fkey FOREIGN KEY (unit_code) REFERENCES public.unit(code) ON DELETE RESTRICT;

--
-- Name: transaction_line transaction_line_shop_id_expense_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_line
    ADD CONSTRAINT transaction_line_shop_id_expense_category_id_fkey FOREIGN KEY (shop_id, expense_category_id) REFERENCES public.expense_category(shop_id, id) ON DELETE RESTRICT;

--
-- Name: transaction_line transaction_line_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_line
    ADD CONSTRAINT transaction_line_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: transaction_line transaction_line_shop_id_item_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_line
    ADD CONSTRAINT transaction_line_shop_id_item_id_fkey FOREIGN KEY (shop_id, item_id) REFERENCES public.shop_item(shop_id, id) ON DELETE RESTRICT;

--
-- Name: transaction_line transaction_line_shop_id_shop_item_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_line
    ADD CONSTRAINT transaction_line_shop_id_shop_item_unit_id_fkey FOREIGN KEY (shop_id, shop_item_unit_id) REFERENCES public.shop_item_unit(shop_id, id) ON DELETE RESTRICT;

--
-- Name: transaction_line transaction_line_shop_id_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_line
    ADD CONSTRAINT transaction_line_shop_id_transaction_id_fkey FOREIGN KEY (shop_id, transaction_id) REFERENCES public.txn(shop_id, id) ON DELETE CASCADE;

--
-- Name: transaction_line transaction_line_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.transaction_line
    ADD CONSTRAINT transaction_line_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unit(id) ON DELETE RESTRICT;

--
-- Name: txn txn_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.txn
    ADD CONSTRAINT txn_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

--
-- Name: txn txn_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.txn
    ADD CONSTRAINT txn_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES public.payment_method(id) ON DELETE RESTRICT;

--
-- Name: txn txn_shop_id_document_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.txn
    ADD CONSTRAINT txn_shop_id_document_id_fkey FOREIGN KEY (shop_id, document_id) REFERENCES public.document(shop_id, id) ON DELETE RESTRICT;

--
-- Name: txn txn_shop_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.txn
    ADD CONSTRAINT txn_shop_id_fkey FOREIGN KEY (shop_id) REFERENCES public.shop(id) ON DELETE CASCADE;

--
-- Name: txn txn_shop_id_party_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.txn
    ADD CONSTRAINT txn_shop_id_party_id_fkey FOREIGN KEY (shop_id, party_id) REFERENCES public.party(shop_id, id) ON DELETE RESTRICT;

--
-- Name: txn txn_shop_id_reverses_transaction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.txn
    ADD CONSTRAINT txn_shop_id_reverses_transaction_id_fkey FOREIGN KEY (shop_id, reverses_transaction_id) REFERENCES public.txn(shop_id, id) ON DELETE RESTRICT;

--
-- Name: txn txn_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.txn
    ADD CONSTRAINT txn_status_id_fkey FOREIGN KEY (status_id) REFERENCES public.transaction_status(id) ON DELETE RESTRICT;

--
-- Name: txn txn_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.txn
    ADD CONSTRAINT txn_type_id_fkey FOREIGN KEY (type_id) REFERENCES public.transaction_type(id) ON DELETE RESTRICT;

--
-- Name: user_preference user_preference_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_preference
    ADD CONSTRAINT user_preference_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

--
-- Name: user_profile user_profile_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_profile
    ADD CONSTRAINT user_profile_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

