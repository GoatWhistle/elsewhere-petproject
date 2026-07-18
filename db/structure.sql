SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

ALTER TABLE IF EXISTS ONLY public.properties DROP CONSTRAINT IF EXISTS fk_rails_26a568e578;
DROP INDEX IF EXISTS public.index_properties_on_point;
DROP INDEX IF EXISTS public.index_properties_on_destination_id;
DROP INDEX IF EXISTS public.index_properties_on_city_code;
DROP INDEX IF EXISTS public.index_properties_on_catalogue_id;
DROP INDEX IF EXISTS public.index_osm_features_on_identity;
DROP INDEX IF EXISTS public.index_osm_features_on_geom;
DROP INDEX IF EXISTS public.index_osm_features_on_city_and_layer;
DROP INDEX IF EXISTS public.index_jobs_on_status;
DROP INDEX IF EXISTS public.index_future_versions_on_session_id;
DROP INDEX IF EXISTS public.index_future_versions_on_lineage_id_and_version;
DROP INDEX IF EXISTS public.index_destinations_on_point;
DROP INDEX IF EXISTS public.index_destinations_on_geography_type;
DROP INDEX IF EXISTS public.index_destinations_on_city_code;
ALTER TABLE IF EXISTS ONLY public.schema_migrations DROP CONSTRAINT IF EXISTS schema_migrations_pkey;
ALTER TABLE IF EXISTS ONLY public.properties DROP CONSTRAINT IF EXISTS properties_pkey;
ALTER TABLE IF EXISTS ONLY public.planning_sessions DROP CONSTRAINT IF EXISTS planning_sessions_pkey;
ALTER TABLE IF EXISTS ONLY public.osm_features DROP CONSTRAINT IF EXISTS osm_features_pkey;
ALTER TABLE IF EXISTS ONLY public.jobs DROP CONSTRAINT IF EXISTS jobs_pkey;
ALTER TABLE IF EXISTS ONLY public.future_versions DROP CONSTRAINT IF EXISTS future_versions_pkey;
ALTER TABLE IF EXISTS ONLY public.destinations DROP CONSTRAINT IF EXISTS destinations_pkey;
ALTER TABLE IF EXISTS ONLY public.ar_internal_metadata DROP CONSTRAINT IF EXISTS ar_internal_metadata_pkey;
ALTER TABLE IF EXISTS public.osm_features ALTER COLUMN id DROP DEFAULT;
DROP TABLE IF EXISTS public.schema_migrations;
DROP TABLE IF EXISTS public.properties;
DROP TABLE IF EXISTS public.planning_sessions;
DROP SEQUENCE IF EXISTS public.osm_features_id_seq;
DROP TABLE IF EXISTS public.osm_features;
DROP TABLE IF EXISTS public.jobs;
DROP TABLE IF EXISTS public.future_versions;
DROP TABLE IF EXISTS public.destinations;
DROP TABLE IF EXISTS public.ar_internal_metadata;
DROP EXTENSION IF EXISTS postgis_topology;
DROP EXTENSION IF EXISTS postgis_tiger_geocoder;
DROP EXTENSION IF EXISTS postgis;
DROP EXTENSION IF EXISTS pgcrypto;
DROP EXTENSION IF EXISTS fuzzystrmatch;
DROP SCHEMA IF EXISTS topology;
DROP SCHEMA IF EXISTS tiger_data;
DROP SCHEMA IF EXISTS tiger;
--
-- Name: tiger; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tiger;


--
-- Name: tiger_data; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA tiger_data;


--
-- Name: topology; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA topology;


--
-- Name: SCHEMA topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA topology IS 'PostGIS Topology schema';


--
-- Name: fuzzystrmatch; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS fuzzystrmatch WITH SCHEMA public;


--
-- Name: EXTENSION fuzzystrmatch; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION fuzzystrmatch IS 'determine similarities and distance between strings';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: postgis_tiger_geocoder; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder WITH SCHEMA tiger;


--
-- Name: EXTENSION postgis_tiger_geocoder; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_tiger_geocoder IS 'PostGIS tiger geocoder and reverse geocoder';


--
-- Name: postgis_topology; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis_topology WITH SCHEMA topology;


--
-- Name: EXTENSION postgis_topology; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis_topology IS 'PostGIS topology spatial types and functions';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: destinations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.destinations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    city_code character varying NOT NULL,
    name character varying NOT NULL,
    country character varying DEFAULT 'RU'::character varying NOT NULL,
    lat numeric(9,6) NOT NULL,
    lon numeric(9,6) NOT NULL,
    source character varying NOT NULL,
    source_slug character varying,
    centre_source character varying DEFAULT 'property_centroid'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    geography_type character varying
);


--
-- Name: future_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.future_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    session_id uuid NOT NULL,
    lineage_id uuid NOT NULL,
    parent_id uuid,
    version integer NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kind character varying NOT NULL,
    status character varying NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: osm_features; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.osm_features (
    id bigint NOT NULL,
    city_code character varying NOT NULL,
    layer character varying NOT NULL,
    osm_type character varying NOT NULL,
    osm_id bigint NOT NULL,
    tags jsonb DEFAULT '{}'::jsonb NOT NULL,
    imported_at timestamp(6) without time zone NOT NULL,
    geom public.geometry(Geometry,4326) NOT NULL
);


--
-- Name: osm_features_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.osm_features_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: osm_features_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.osm_features_id_seq OWNED BY public.osm_features.id;


--
-- Name: planning_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planning_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: properties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.properties (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    catalogue_id character varying NOT NULL,
    source character varying NOT NULL,
    destination_id uuid NOT NULL,
    city_code character varying NOT NULL,
    name character varying NOT NULL,
    lat numeric(9,6) NOT NULL,
    lon numeric(9,6) NOT NULL,
    address character varying,
    rating numeric(3,1),
    rating_scale integer,
    review_count integer,
    price_level_minor bigint,
    price_currency character varying(3),
    price_level_text character varying,
    photos jsonb DEFAULT '[]'::jsonb NOT NULL,
    source_url character varying NOT NULL,
    harvested_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    price_level_note character varying
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: osm_features id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_features ALTER COLUMN id SET DEFAULT nextval('public.osm_features_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: destinations destinations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.destinations
    ADD CONSTRAINT destinations_pkey PRIMARY KEY (id);


--
-- Name: future_versions future_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.future_versions
    ADD CONSTRAINT future_versions_pkey PRIMARY KEY (id);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- Name: osm_features osm_features_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_features
    ADD CONSTRAINT osm_features_pkey PRIMARY KEY (id);


--
-- Name: planning_sessions planning_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planning_sessions
    ADD CONSTRAINT planning_sessions_pkey PRIMARY KEY (id);


--
-- Name: properties properties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT properties_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: index_destinations_on_city_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_destinations_on_city_code ON public.destinations USING btree (city_code);


--
-- Name: index_destinations_on_geography_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_destinations_on_geography_type ON public.destinations USING btree (geography_type);


--
-- Name: index_destinations_on_point; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_destinations_on_point ON public.destinations USING gist (((public.st_setsrid(public.st_makepoint((lon)::double precision, (lat)::double precision), 4326))::public.geography));


--
-- Name: index_future_versions_on_lineage_id_and_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_future_versions_on_lineage_id_and_version ON public.future_versions USING btree (lineage_id, version);


--
-- Name: index_future_versions_on_session_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_future_versions_on_session_id ON public.future_versions USING btree (session_id);


--
-- Name: index_jobs_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_jobs_on_status ON public.jobs USING btree (status);


--
-- Name: index_osm_features_on_city_and_layer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_osm_features_on_city_and_layer ON public.osm_features USING btree (city_code, layer);


--
-- Name: index_osm_features_on_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_osm_features_on_geom ON public.osm_features USING gist (geom);


--
-- Name: index_osm_features_on_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_osm_features_on_identity ON public.osm_features USING btree (city_code, layer, osm_type, osm_id);


--
-- Name: index_properties_on_catalogue_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_properties_on_catalogue_id ON public.properties USING btree (catalogue_id);


--
-- Name: index_properties_on_city_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_properties_on_city_code ON public.properties USING btree (city_code);


--
-- Name: index_properties_on_destination_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_properties_on_destination_id ON public.properties USING btree (destination_id);


--
-- Name: index_properties_on_point; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_properties_on_point ON public.properties USING gist (((public.st_setsrid(public.st_makepoint((lon)::double precision, (lat)::double precision), 4326))::public.geography));


--
-- Name: properties fk_rails_26a568e578; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.properties
    ADD CONSTRAINT fk_rails_26a568e578 FOREIGN KEY (destination_id) REFERENCES public.destinations(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO public;

INSERT INTO "schema_migrations" (version) VALUES
('20260720090000'),
('20260719100000'),
('20260719090000'),
('20260718090000'),
('20260702090000');

