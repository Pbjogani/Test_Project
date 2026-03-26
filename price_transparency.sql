use cnc_FWA_DW
go

-- ============================================================
-- Price Transparency Data from Payer Websites
-- ============================================================
-- Creates staging and reporting tables for payer price
-- transparency machine-readable files (MRFs) as required
-- by the Transparency in Coverage (TiC) rule.
-- ============================================================

-- Staging table for raw in-network rate data ingested from payer MRF files
if object_id('phi.stg_payer_innetwork_rates', 'U') is null
begin
    create table phi.stg_payer_innetwork_rates (
        innetwork_rate_sid        int identity(1,1)  not null,
        payer_name                varchar(255)       not null,
        plan_name                 varchar(255)       not null,
        plan_id                   varchar(50)        null,
        plan_id_type              varchar(50)        null,
        billing_code              varchar(50)        not null,
        billing_code_type         varchar(50)        not null,  -- e.g. CPT, HCPCS, DRG
        billing_code_type_version varchar(20)        null,
        description               varchar(500)       null,
        negotiation_arrangement   varchar(50)        null,      -- e.g. ffs, bundle, capitation
        negotiated_type           varchar(50)        null,      -- e.g. negotiated, derived, fee schedule
        negotiated_rate           decimal(18, 4)     not null,
        expiration_date           date               null,
        billing_class             varchar(50)        null,      -- e.g. professional, institutional
        service_code              varchar(10)        null,
        provider_npi              varchar(20)        null,
        tin_type                  varchar(10)        null,      -- ein or npi
        tin_value                 varchar(20)        null,
        source_file_name          varchar(500)       null,
        load_date                 datetime           not null default getdate(),
        audit_sid                 int                null,
        constraint pk_stg_payer_innetwork_rates primary key (innetwork_rate_sid)
    )
end

-- Staging table for raw out-of-network allowed amount data
if object_id('phi.stg_payer_outofnetwork_rates', 'U') is null
begin
    create table phi.stg_payer_outofnetwork_rates (
        outofnetwork_rate_sid     int identity(1,1)  not null,
        payer_name                varchar(255)       not null,
        plan_name                 varchar(255)       not null,
        plan_id                   varchar(50)        null,
        plan_id_type              varchar(50)        null,
        billing_code              varchar(50)        not null,
        billing_code_type         varchar(50)        not null,
        billing_code_type_version varchar(20)        null,
        description               varchar(500)       null,
        allowed_amount            decimal(18, 4)     not null,
        service_code              varchar(10)        null,
        provider_npi              varchar(20)        null,
        tin_type                  varchar(10)        null,
        tin_value                 varchar(20)        null,
        billed_charge             decimal(18, 4)     null,
        source_file_name          varchar(500)       null,
        load_date                 datetime           not null default getdate(),
        audit_sid                 int                null,
        constraint pk_stg_payer_outofnetwork_rates primary key (outofnetwork_rate_sid)
    )
end

-- Audit log table to track payer MRF file loads
if object_id('phi.payer_mrf_audit', 'U') is null
begin
    create table phi.payer_mrf_audit (
        audit_sid               int identity(1,1)  not null,
        payer_name              varchar(255)       not null,
        plan_name               varchar(255)       null,
        source_file_name        varchar(500)       not null,
        file_type               varchar(50)        not null,  -- in-network, out-of-network, table-of-contents
        reporting_entity_name   varchar(255)       null,
        reporting_entity_type   varchar(50)        null,      -- health insurance issuer or group health plan
        last_updated_on         date               null,
        records_loaded          int                null,
        load_start_datetime     datetime           null,
        load_end_datetime       datetime           null,
        load_status             varchar(50)        null,      -- SUCCESS, FAILED, IN_PROGRESS
        error_message           varchar(max)       null,
        created_datetime        datetime           not null default getdate(),
        constraint pk_payer_mrf_audit primary key (audit_sid)
    )
end

-- ============================================================
-- Reporting Queries
-- ============================================================

-- Summary of in-network rates by payer and billing code type
select
    payer_name,
    billing_code_type,
    count(*)                    as rate_count,
    avg(negotiated_rate)        as avg_negotiated_rate,
    min(negotiated_rate)        as min_negotiated_rate,
    max(negotiated_rate)        as max_negotiated_rate,
    max(load_date)              as last_load_date
from phi.stg_payer_innetwork_rates
group by
    payer_name,
    billing_code_type
order by
    payer_name,
    billing_code_type

-- Stored procedure: look up in-network rates for a specific billing code across all payers
if object_id('phi.usp_get_innetwork_rates_by_code', 'P') is not null
    drop procedure phi.usp_get_innetwork_rates_by_code
go

create procedure phi.usp_get_innetwork_rates_by_code
    @billing_code       varchar(50),
    @billing_code_type  varchar(50) = 'CPT'
as
begin
    set nocount on

    select
        payer_name,
        plan_name,
        billing_code,
        billing_code_type,
        description,
        negotiation_arrangement,
        negotiated_type,
        negotiated_rate,
        expiration_date,
        billing_class,
        provider_npi,
        load_date
    from phi.stg_payer_innetwork_rates
    where billing_code = @billing_code
      and billing_code_type = @billing_code_type
    order by
        negotiated_rate,
        payer_name
end
go

-- Audit summary for MRF file loads
select
    a.audit_sid,
    a.payer_name,
    a.plan_name,
    a.source_file_name,
    a.file_type,
    a.reporting_entity_name,
    a.last_updated_on,
    a.records_loaded,
    a.load_status,
    a.load_start_datetime,
    a.load_end_datetime,
    datediff(second, a.load_start_datetime, a.load_end_datetime) as load_duration_seconds
from phi.payer_mrf_audit a
order by
    a.created_datetime desc
