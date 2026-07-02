CREATE EXTENSION IF NOT EXISTS postgis;

-- Supply owns all catalogue, geo, climate, calibration and fare snapshots.
CREATE TABLE IF NOT EXISTS destinations (city_code text PRIMARY KEY, name text NOT NULL, country text NOT NULL, coordinates geography(Point, 4326));
CREATE TABLE IF NOT EXISTS properties (catalogue_id text PRIMARY KEY, city_code text NOT NULL, name text NOT NULL, coordinates geography(Point, 4326), rating numeric, price_level_minor integer);
CREATE TABLE IF NOT EXISTS property_geo_features (property_id text PRIMARY KEY, distance_to_sea_m integer, distance_to_centre_m integer, poi_density numeric, restaurant_count_500m integer, nearest_major_road_m integer, road_class text, airport_distance_m integer);
CREATE TABLE IF NOT EXISTS destination_climate_normals (city_code text, month integer, temp_mean_c numeric, rain_days integer, sea_temp_c numeric);
CREATE TABLE IF NOT EXISTS price_calibrations (property_id text PRIMARY KEY, observed_level_minor integer NOT NULL, formula_version text NOT NULL);
CREATE TABLE IF NOT EXISTS flight_fare_snapshots (id uuid PRIMARY KEY, origin text NOT NULL, destination text NOT NULL, amount_minor integer NOT NULL, currency text NOT NULL, as_of timestamptz NOT NULL);

-- Planning owns the decision state. No cross-context foreign keys or joins.
CREATE TABLE IF NOT EXISTS planning_sessions (id uuid PRIMARY KEY, dream text NOT NULL, origin text NOT NULL);
CREATE TABLE IF NOT EXISTS travel_dna_elements (id uuid PRIMARY KEY, session_id uuid NOT NULL, dimension text NOT NULL, kind text NOT NULL, target jsonb, weight numeric, provenance text NOT NULL, confidence numeric NOT NULL);
CREATE TABLE IF NOT EXISTS clarifications (id uuid PRIMARY KEY, session_id uuid NOT NULL, payload jsonb NOT NULL);
CREATE TABLE IF NOT EXISTS futures (id uuid PRIMARY KEY, session_id uuid NOT NULL, lineage_id uuid NOT NULL);
CREATE TABLE IF NOT EXISTS future_versions (id uuid PRIMARY KEY, future_id uuid NOT NULL, parent_id uuid, payload jsonb NOT NULL);
CREATE TABLE IF NOT EXISTS future_components (id uuid PRIMARY KEY, future_version_id uuid NOT NULL, kind text NOT NULL, amount_minor integer NOT NULL, fulfilment text NOT NULL);
CREATE TABLE IF NOT EXISTS match_scores (future_version_id uuid PRIMARY KEY, score numeric NOT NULL, confidence numeric NOT NULL);
CREATE TABLE IF NOT EXISTS match_contributions (id uuid PRIMARY KEY, future_version_id uuid NOT NULL, dimension text NOT NULL, contribution numeric NOT NULL);
CREATE TABLE IF NOT EXISTS deltas (id uuid PRIMARY KEY, future_version_id uuid NOT NULL, parent_id uuid NOT NULL, payload jsonb NOT NULL);
CREATE TABLE IF NOT EXISTS delta_items (id uuid PRIMARY KEY, delta_id uuid NOT NULL, description text NOT NULL, amount_minor integer NOT NULL);

-- Foresight owns evidence and mitigations; it only stores a Future id.
CREATE TABLE IF NOT EXISTS forecasts (id uuid PRIMARY KEY, future_version_id uuid NOT NULL, generated_at timestamptz NOT NULL);
CREATE TABLE IF NOT EXISTS risk_items (id uuid PRIMARY KEY, forecast_id uuid NOT NULL, risk_type text NOT NULL, severity text NOT NULL, claim_kind text NOT NULL);
CREATE TABLE IF NOT EXISTS risk_evidence (id uuid PRIMARY KEY, risk_item_id uuid NOT NULL, source text NOT NULL, excerpt text);
CREATE TABLE IF NOT EXISTS mitigations (id uuid PRIMARY KEY, risk_item_id uuid NOT NULL, payload jsonb NOT NULL);

