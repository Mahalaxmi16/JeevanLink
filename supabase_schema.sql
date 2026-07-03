-- ====================================================================================
-- JeevanLink Database Setup Script
-- ====================================================================================
-- Instructions:
-- 1. Go to your Supabase project dashboard.
-- 2. On the left menu, click on "SQL Editor".
-- 3. Click "+ New query".
-- 4. Copy the entire content of this file and paste it into the editor.
-- 5. Click "RUN".
-- ====================================================================================

-- ====================================================================================
-- TABLE 1: profiles
-- ====================================================================================
-- This table stores public information for all users (donors and hospitals).
-- It is linked to the authentication users table via the id column.
-- ====================================================================================

CREATE TABLE public.profiles (
id uuid NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
created_at timestamp with time zone DEFAULT now() NOT NULL,
phone text UNIQUE,
full_name text,
role text,
blood_type text,
hospital_name text,
latitude double precision,
longitude double precision
);

-- Add comments to the table and columns for clarity
COMMENT ON TABLE public.profiles IS 'Stores public profile information for donors and hospitals.';
COMMENT ON COLUMN public.profiles.id IS 'Links to the auth.users table.';
COMMENT ON COLUMN public.profiles.role IS 'User role, e.g., ''donor'' or ''hospital''.';

-- ====================================================================================
-- TABLE 2: blood_requests
-- ====================================================================================
-- This table will store all active and past blood requests made by hospitals.
-- ====================================================================================

CREATE TABLE public.blood_requests (
id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
created_at timestamp with time zone DEFAULT now() NOT NULL,
requesting_hospital_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
blood_type text NOT NULL,
status text DEFAULT 'active'::text NOT NULL, -- e.g., 'active', 'fulfilled', 'cancelled'
notes text
);

COMMENT ON TABLE public.blood_requests IS 'Stores blood donation requests from hospitals.';
COMMENT ON COLUMN public.blood_requests.requesting_hospital_id IS 'The ID of the hospital that made the request.';
COMMENT ON COLUMN public.blood_requests.status IS 'The current status of the blood request.';

-- ====================================================================================
-- ROW LEVEL SECURITY (RLS) SETUP
-- ====================================================================================
-- These policies are essential for securing your data. They ensure that users can
-- only access and modify data they are permitted to.
-- ====================================================================================

-- First, enable RLS on the tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blood_requests ENABLE ROW LEVEL SECURITY;

-- POLICIES FOR: profiles table

-- 1. Allow users to insert their own profile
CREATE POLICY "Allow users to insert their own profile"
ON public.profiles FOR INSERT
WITH CHECK (auth.uid() = id);

-- 2. Allow users to view their own profile
CREATE POLICY "Allow users to view their own profile"
ON public.profiles FOR SELECT
USING (auth.uid() = id);

-- 3. Allow logged-in users to see other profiles (e.g., for hospitals to see donors)
CREATE POLICY "Allow authenticated users to view all profiles"
ON public.profiles FOR SELECT
USING (auth.role() = 'authenticated');

-- 4. Allow users to update their own profile
CREATE POLICY "Allow users to update their own profile"
ON public.profiles FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- POLICIES FOR: blood_requests table

-- 1. Allow hospitals to create blood requests
CREATE POLICY "Allow hospitals to create blood requests"
ON public.blood_requests FOR INSERT
WITH CHECK (
-- Check that the user has the 'hospital' role in their profile
(SELECT role FROM public.profiles WHERE id = auth.uid()) = 'hospital'
AND
-- Ensure the request is being made on behalf of themselves
requesting_hospital_id = auth.uid()
);

-- 2. Allow any authenticated user to see all active blood requests
CREATE POLICY "Allow authenticated users to view active requests"
ON public.blood_requests FOR SELECT
USING (auth.role() = 'authenticated');

-- 3. Allow hospitals to update their own requests (e.g., to change status to 'fulfilled')
CREATE POLICY "Allow hospitals to update their own requests"
ON public.blood_requests FOR UPDATE
USING (
(SELECT role FROM public.profiles WHERE id = auth.uid()) = 'hospital'
AND
requesting_hospital_id = auth.uid()
);


-- ====================================================================================
-- JeevanLink Database Update Script 1
-- ====================================================================================
-- This script adds the donor_responses table to track donation commitments.
-- ====================================================================================

-- ====================================================================================
-- TABLE 3: donor_responses
-- ====================================================================================
-- This table links a donor (from profiles) to a specific blood_request.
-- ====================================================================================

CREATE TABLE public.donor_responses (
id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
created_at timestamp with time zone DEFAULT now() NOT NULL,
request_id uuid NOT NULL REFERENCES public.blood_requests(id) ON DELETE CASCADE,
donor_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
response_status text DEFAULT 'accepted'::text NOT NULL -- e.g., 'accepted', 'declined'
);

COMMENT ON TABLE public.donor_responses IS 'Tracks donor responses to blood requests.';

-- ====================================================================================
-- ROW LEVEL SECURITY (RLS) SETUP for donor_responses
-- ====================================================================================

-- First, enable RLS on the new table
ALTER TABLE public.donor_responses ENABLE ROW LEVEL SECURITY;

-- 1. Allow donors to insert their own response
CREATE POLICY "Allow donors to insert their own response"
ON public.donor_responses FOR INSERT
WITH CHECK (auth.uid() = donor_id);

-- 2. Allow donors to view their own responses
CREATE POLICY "Allow donors to view their own responses"
ON public.donor_responses FOR SELECT
USING (auth.uid() = donor_id);

-- 3. Allow hospitals to view responses to their own blood requests
CREATE POLICY "Allow hospitals to view responses to their requests"
ON public.donor_responses FOR SELECT
USING (
(SELECT role FROM public.profiles WHERE id = auth.uid()) = 'hospital'
AND
EXISTS (
SELECT 1
FROM public.blood_requests
WHERE
id = donor_responses.request_id AND
requesting_hospital_id = auth.uid()
)
);

-==========
-- ====================================================================================
-- JeevanLink Database Update Script 2
-- ====================================================================================
-- This script adds location-based search functionality.
-- ====================================================================================

-- STEP 1: Enable PostGIS Extension
-- PostGIS is a powerful extension for PostgreSQL (the database Supabase uses)
-- that allows for geographic location queries. This might already be enabled.
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

-- STEP 2: Create a function to find nearby blood requests
-- This is a remote procedure call (RPC) function. Our Flutter app will call this
-- function to get a list of requests tailored to the donor's location.
CREATE OR REPLACE FUNCTION get_nearby_requests(
donor_lat float,
donor_lon float
)
RETURNS SETOF blood_requests -- The function will return a list of rows from our blood_requests table
AS $$
BEGIN
-- This is the core logic. It calculates the distance between the donor
-- and the hospital that made the request.
RETURN QUERY
SELECT br.*
FROM public.blood_requests AS br
JOIN public.profiles AS p ON br.requesting_hospital_id = p.id
WHERE
br.status = 'active' AND
-- Use PostGIS st_distance to find hospitals within a 50km radius.
-- The distance is in meters, so 50,000 meters = 50 km.
extensions.st_distance(
extensions.st_point(p.longitude, p.latitude)::geography,
extensions.st_point(donor_lon, donor_lat)::geography
) < 50000;
END;
$$ LANGUAGE plpgsql;

-- ====================================================================================
-- What this script does:
-- 1. It ensures the PostGIS extension is ready to use.
-- 2. It creates a new function called get_nearby_requests that your app can call.
-- 3. When called, this function will only return active blood requests from hospitals
--    that are within a 50-kilometer radius of the donor's current location.
-- ====================================================================================



-- Step 1: Enable PostGIS Extension if not already enabled.
-- PostGIS gives our database geographic superpowers, essential for location-based queries.
CREATE EXTENSION IF NOT EXISTS postgis;

-- Step 2: Add a geography column to the profiles table.
-- This will store user locations in a format optimized for geographic calculations.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS location geography(Point, 4326);

-- Step 3: Add a geography column to the blood_requests table.
-- This will store hospital locations for requests.
ALTER TABLE public.blood_requests ADD COLUMN IF NOT EXISTS location geography(Point, 4326);

-- Step 3.5: Ensure hospital_id column exists in blood_requests table.
-- This column links a request back to the hospital that created it.
ALTER TABLE public.blood_requests ADD COLUMN IF NOT EXISTS hospital_id uuid REFERENCES public.profiles(id);

-- Step 4: Create a trigger function to automatically update the geography columns.
-- This function runs automatically whenever a profile or request is created or updated,
-- converting latitude/longitude into the more efficient geography format.
CREATE OR REPLACE FUNCTION update_geography_column()
RETURNS TRIGGER AS $$
BEGIN
NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 5: Attach the trigger to the profiles table.
DROP TRIGGER IF EXISTS trigger_update_profiles_location ON public.profiles;
CREATE TRIGGER trigger_update_profiles_location
BEFORE INSERT OR UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION update_geography_column();

-- Step 6: Attach the trigger to the blood_requests table.
DROP TRIGGER IF EXISTS trigger_update_blood_requests_location ON public.blood_requests;
CREATE TRIGGER trigger_update_blood_requests_location
BEFORE INSERT OR UPDATE ON public.blood_requests
FOR EACH ROW EXECUTE FUNCTION update_geography_column();

-- Step 7: Create the notifications table.
-- This table will log every notification that needs to be sent to a donor.
-- Our matchmaking algorithm will add entries here.
CREATE TABLE IF NOT EXISTS public.notifications (
id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
created_at timestamp with time zone DEFAULT now() NOT NULL,
request_id uuid REFERENCES public.blood_requests(id) ON DELETE CASCADE,
donor_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
status text DEFAULT 'pending' NOT NULL, -- e.g., pending, sent, failed
CONSTRAINT notifications_unique_request_donor UNIQUE (request_id, donor_id)
);

-- Step 8: Set up security for the notifications table.
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Donors can view their own notifications." ON public.notifications;
CREATE POLICY "Donors can view their own notifications."
ON public.notifications FOR SELECT
USING (auth.uid() = donor_id);

-- Step 9: Create the donor_tracking table for live location updates.
-- This table will store the real-time location of donors who are on their way.
CREATE TABLE IF NOT EXISTS public.donor_tracking (
id bigint GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
response_id uuid REFERENCES public.donor_responses(id) ON DELETE CASCADE UNIQUE,
donor_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
request_id uuid REFERENCES public.blood_requests(id) ON DELETE CASCADE,
last_known_location geography(Point, 4326),
status text DEFAULT 'accepted' NOT NULL, -- e.g., accepted, on_my_way, arrived
updated_at timestamp with time zone DEFAULT now()
);

-- Step 10: Set up security for the donor_tracking table.
ALTER TABLE public.donor_tracking ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow full access for relevant users." ON public.donor_tracking;
CREATE POLICY "Allow full access for relevant users."
ON public.donor_tracking FOR ALL
USING (
-- Donors can manage their own tracking data.
auth.uid() = donor_id OR
-- Hospitals can view tracking data for their requests.
(
SELECT role FROM public.profiles WHERE id = auth.uid()
) = 'hospital' AND request_id IN (
SELECT id FROM public.blood_requests WHERE hospital_id = auth.uid()
)
);

-- Step 11: Create the matchmaking database function.
-- This is the intelligent heart of the app. It finds and notifies nearby donors.
CREATE OR REPLACE FUNCTION public.start_matchmaking_for_request(request_id_param uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
request_record record;
donor_record record;
search_radius int := 5000; -- Start with 5km radius
time_limit int := 3000; -- 50 minutes in seconds
interval_time int := 600; -- 10 minutes in seconds
elapsed_time int := 0;
BEGIN
-- Get the details of the newly created blood request
SELECT * INTO request_record FROM public.blood_requests WHERE id = request_id_param;

-- Loop for the specified time limit
WHILE elapsed_time < time_limit LOOP
-- Find matching donors within the current search radius who haven't been notified yet
FOR donor_record IN
SELECT prof.id
FROM public.profiles prof
WHERE
prof.role = 'donor' AND
prof.blood_type = request_record.blood_type AND
ST_DWithin(prof.location, request_record.location, search_radius) AND
NOT EXISTS (
SELECT 1 FROM public.notifications n
WHERE n.donor_id = prof.id AND n.request_id = request_id_param
)
LOOP
-- Insert a notification record for each matched donor
INSERT INTO public.notifications (request_id, donor_id, status)
VALUES (request_id_param, donor_record.id, 'pending');
END LOOP;

-- Wait for the interval before the next loop
PERFORM pg_sleep(interval_time);
elapsed_time := elapsed_time + interval_time;

-- Increase the search radius for the next iteration (e.g., double it)
search_radius := search_radius * 2;

END LOOP;
END;
$$;

-- Step 12: Create a trigger to automatically start the matchmaking process.
-- This trigger calls the matchmaking function whenever a new blood request is created.
CREATE OR REPLACE FUNCTION public.handle_new_blood_request()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
-- We must run this in the background so the app doesn't freeze.
-- Supabase doesn't directly support background jobs from triggers,
-- but for demonstration, we call it directly.
-- In production, you would use a background worker or a scheduled task.

-- For now, this will be handled via a direct call in the app after request creation,
-- as true background jobs from triggers are complex. We will adjust the app code
-- to call start_matchmaking_for_request(new.id).
RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS on_blood_request_created ON public.blood_requests;
CREATE TRIGGER on_blood_request_created
AFTER INSERT ON public.blood_requests
FOR EACH ROW EXECUTE PROCEDURE public.handle_new_blood_request();


-- In order to track the expanding search for each request,
-- we need to add a new column to our blood_requests table.
-- This column will store the current "level" of the search radius.

ALTER TABLE public.blood_requests
ADD COLUMN expansion_level SMALLINT DEFAULT 0 NOT NULL;

-- This column will start at 0 (the initial 10km search) and will
-- be increased by our automated function every 10 minutes if
-- not enough donors have responded.

-- Adding this column is a non-breaking change and prepares our database
-- for the first AI enhancement.

ALTER TABLE public.profiles
ADD COLUMN availability_score REAL DEFAULT 0.5;


-- In Supabase SQL Editor, create a custom function
CREATE OR REPLACE FUNCTION send_custom_otp(phone_number text, otp_code text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Custom Twilio API call with your message
  PERFORM net.http_post(
    'https://api.twilio.com/2010-04-01/Accounts/YOUR_TWILIO_ACCOUNT_SID/Messages.json',
    jsonb_build_object(
      'To', phone_number,
      'From', '+16515056928',
      'Body', 'Sent from JeevanLink - Your OTP is ' || otp_code
    )
  );
END;
$$;

-- Add missing column
ALTER TABLE public.blood_requests 
ADD COLUMN IF NOT EXISTS units_required INTEGER DEFAULT 1;

-- Create the function your Flutter app is calling
CREATE OR REPLACE FUNCTION public.match_donors_and_notify(
  request_id_param uuid,
  blood_type_param text,
  initial_radius_km numeric DEFAULT 10.0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  request_record record;
  donor_record record;
  hospital_record record;
  search_radius_m numeric;
BEGIN
  -- Get request and hospital details
  SELECT * INTO request_record FROM public.blood_requests WHERE id = request_id_param;
  SELECT * INTO hospital_record FROM public.profiles WHERE id = request_record.requesting_hospital_id;
  
  search_radius_m := initial_radius_km * 1000;
  
  -- Find compatible donors
  FOR donor_record IN
    SELECT p.id
    FROM public.profiles p
    WHERE 
      p.role = 'donor' 
      AND p.blood_type = blood_type_param
      AND p.latitude IS NOT NULL 
      AND p.longitude IS NOT NULL
      AND (
        6371000 * acos(
          cos(radians(hospital_record.latitude)) * 
          cos(radians(p.latitude)) * 
          cos(radians(p.longitude) - radians(hospital_record.longitude)) + 
          sin(radians(hospital_record.latitude)) * 
          sin(radians(p.latitude))
        )
      ) <= search_radius_m
      AND NOT EXISTS (
        SELECT 1 FROM public.notifications n 
        WHERE n.donor_id = p.id AND n.request_id = request_id_param
      )
  LOOP
    -- Create notification
    INSERT INTO public.notifications (request_id, donor_id, status)
    VALUES (request_id_param, donor_record.id, 'pending')
    ON CONFLICT (request_id, donor_id) DO NOTHING;
  END LOOP;
END;
$$;


-- ====================================================================================
-- AI-Powered Donor Prioritization System for JeevanLink
-- ====================================================================================

-- Step 1: Add tracking columns for ML features
-- ====================================================================================

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS response_count INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS successful_donations INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS last_response_time TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS average_response_time_minutes INTEGER DEFAULT 30;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS preferred_time_slots TEXT[]; -- e.g., ['morning', 'evening']
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS reliability_score REAL DEFAULT 0.5;

-- Add response tracking to notifications
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS response_time_minutes INTEGER;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS responded_at TIMESTAMP WITH TIME ZONE;

-- Step 2: Create ML feature calculation function
-- ====================================================================================

CREATE OR REPLACE FUNCTION calculate_donor_availability_score(donor_id_param uuid, request_urgency text DEFAULT 'normal')
RETURNS REAL
LANGUAGE plpgsql
AS $$
DECLARE
    donor_profile record;
    base_score real := 0.5;
    time_factor real := 1.0;
    reliability_factor real := 1.0;
    recency_factor real := 1.0;
    distance_factor real := 1.0;
    final_score real;
    current_hour integer;
BEGIN
    -- Get donor profile data
    SELECT * INTO donor_profile FROM public.profiles WHERE id = donor_id_param;
    
    -- Factor 1: Historical reliability (response rate)
    IF donor_profile.response_count > 0 THEN
        reliability_factor := LEAST(
            donor_profile.successful_donations::real / donor_profile.response_count::real * 2.0,
            2.0
        );
    END IF;
    
    -- Factor 2: Time-based availability
    current_hour := EXTRACT(HOUR FROM NOW());
    
    -- Higher score during typical donation hours (9 AM - 8 PM)
    IF current_hour BETWEEN 9 AND 20 THEN
        time_factor := 1.2;
    ELSE
        time_factor := 0.8;
    END IF;
    
    -- Factor 3: Recency of last donation (encourage regular donors, but not too frequent)
    IF donor_profile.last_response_time IS NOT NULL THEN
        CASE 
            WHEN donor_profile.last_response_time > NOW() - INTERVAL '1 month' THEN
                recency_factor := 1.3; -- Recently active
            WHEN donor_profile.last_response_time > NOW() - INTERVAL '3 months' THEN
                recency_factor := 1.0; -- Moderately active
            WHEN donor_profile.last_response_time > NOW() - INTERVAL '6 months' THEN
                recency_factor := 0.8; -- Less active
            ELSE
                recency_factor := 0.6; -- Inactive
        END CASE;
    END IF;
    
    -- Factor 4: Response speed (faster responders get higher priority)
    IF donor_profile.average_response_time_minutes <= 10 THEN
        time_factor := time_factor * 1.3;
    ELSIF donor_profile.average_response_time_minutes <= 30 THEN
        time_factor := time_factor * 1.1;
    END IF;
    
    -- Calculate final score
    final_score := base_score * reliability_factor * time_factor * recency_factor;
    
    -- Ensure score stays within bounds
    final_score := GREATEST(LEAST(final_score, 1.0), 0.1);
    
    -- Update the donor's current availability score
    UPDATE public.profiles 
    SET availability_score = final_score 
    WHERE id = donor_id_param;
    
    RETURN final_score;
END;
$$;

-- Step 3: Enhanced matchmaking function with AI prioritization
-- ====================================================================================

CREATE OR REPLACE FUNCTION public.match_donors_and_notify_ai(
  request_id_param uuid,
  blood_type_param text,
  initial_radius_km numeric DEFAULT 10.0,
  max_donors_to_notify integer DEFAULT 10
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  request_record record;
  donor_record record;
  hospital_record record;
  search_radius_m numeric;
  urgency_level text := 'normal';
BEGIN
  -- Get request and hospital details
  SELECT * INTO request_record FROM public.blood_requests WHERE id = request_id_param;
  SELECT * INTO hospital_record FROM public.profiles WHERE id = request_record.requesting_hospital_id;
  
  search_radius_m := initial_radius_km * 1000;
  
  -- Determine urgency based on blood type and units
  IF blood_type_param = 'O-' OR request_record.units_required >= 4 THEN
    urgency_level := 'critical';
    max_donors_to_notify := max_donors_to_notify * 2; -- Notify more donors for critical cases
  END IF;
  
  -- Find and prioritize compatible donors using AI scoring
  FOR donor_record IN
    WITH scored_donors AS (
      SELECT 
        p.id,
        p.full_name,
        p.phone,
        p.blood_type,
        p.latitude,
        p.longitude,
        -- Calculate real-time availability score
        calculate_donor_availability_score(p.id, urgency_level) as ai_score,
        -- Calculate distance
        (
          6371000 * acos(
            cos(radians(hospital_record.latitude)) * 
            cos(radians(p.latitude)) * 
            cos(radians(p.longitude) - radians(hospital_record.longitude)) + 
            sin(radians(hospital_record.latitude)) * 
            sin(radians(p.latitude))
          )
        ) as distance_m
      FROM public.profiles p
      WHERE 
        p.role = 'donor' 
        AND (
          p.blood_type = blood_type_param OR 
          (blood_type_param = 'AB+') OR
          (blood_type_param = 'AB-' AND p.blood_type IN ('A-', 'B-', 'AB-', 'O-')) OR
          (blood_type_param = 'A+' AND p.blood_type IN ('A+', 'A-', 'O+', 'O-')) OR
          (blood_type_param = 'A-' AND p.blood_type IN ('A-', 'O-')) OR
          (blood_type_param = 'B+' AND p.blood_type IN ('B+', 'B-', 'O+', 'O-')) OR
          (blood_type_param = 'B-' AND p.blood_type IN ('B-', 'O-')) OR
          (blood_type_param = 'O+' AND p.blood_type IN ('O+', 'O-')) OR
          (blood_type_param = 'O-' AND p.blood_type = 'O-')
        )
        AND p.latitude IS NOT NULL 
        AND p.longitude IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.notifications n 
          WHERE n.donor_id = p.id AND n.request_id = request_id_param
        )
    )
    SELECT * FROM scored_donors 
    WHERE distance_m <= search_radius_m
    ORDER BY 
      -- Primary sort: AI availability score (higher is better)
      ai_score DESC,
      -- Secondary sort: distance (closer is better)
      distance_m ASC
    LIMIT max_donors_to_notify
  LOOP
    -- Create notification with priority ranking
    INSERT INTO public.notifications (request_id, donor_id, status)
    VALUES (request_id_param, donor_record.id, 'pending')
    ON CONFLICT (request_id, donor_id) DO NOTHING;
    
    -- Optional: Send SMS with priority indicator
    -- PERFORM send_prioritized_sms(donor_record.phone, hospital_record.hospital_name, blood_type_param, urgency_level);
  END LOOP;
  
  -- Log AI matching results
  RAISE NOTICE 'AI matching completed for request % with urgency level %', request_id_param, urgency_level;
END;
$$;

-- Step 4: Update donor metrics when they respond
-- ====================================================================================

CREATE OR REPLACE FUNCTION update_donor_response_metrics()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Update notification with response time
  UPDATE public.notifications 
  SET 
    responded_at = NOW(),
    response_time_minutes = EXTRACT(EPOCH FROM (NOW() - created_at))/60,
    status = 'accepted'
  WHERE request_id = NEW.request_id AND donor_id = NEW.donor_id;
  
  -- Update donor profile metrics
  UPDATE public.profiles 
  SET 
    response_count = response_count + 1,
    last_response_time = NOW(),
    successful_donations = CASE WHEN NEW.response_status = 'accepted' THEN successful_donations + 1 ELSE successful_donations END,
    -- Update average response time with exponential moving average
    average_response_time_minutes = COALESCE(
      (average_response_time_minutes * 0.7 + 
       (SELECT response_time_minutes FROM public.notifications 
        WHERE request_id = NEW.request_id AND donor_id = NEW.donor_id) * 0.3),
      30
    )
  WHERE id = NEW.donor_id;
  
  RETURN NEW;
END;
$$;

-- Attach trigger to donor_responses table
DROP TRIGGER IF EXISTS update_donor_metrics_on_response ON public.donor_responses;
CREATE TRIGGER update_donor_metrics_on_response
  AFTER INSERT ON public.donor_responses
  FOR EACH ROW
  EXECUTE FUNCTION update_donor_response_metrics();

-- Step 5: ML model integration endpoint (for future advanced ML)
-- ====================================================================================

CREATE OR REPLACE FUNCTION get_donor_features_for_ml(donor_id_param uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'donor_id', p.id,
    'response_count', p.response_count,
    'successful_donations', p.successful_donations,
    'reliability_score', p.reliability_score,
    'avg_response_time', p.average_response_time_minutes,
    'days_since_last_response', COALESCE(
      EXTRACT(DAYS FROM (NOW() - p.last_response_time)), 
      365
    ),
    'current_hour', EXTRACT(HOUR FROM NOW()),
    'day_of_week', EXTRACT(DOW FROM NOW()),
    'blood_type', p.blood_type,
    'availability_score', p.availability_score
  ) INTO result
  FROM public.profiles p
  WHERE p.id = donor_id_param AND p.role = 'donor';
  
  RETURN result;
END;
$$;

-- Fix for hospital requests - ensure requesting_hospital_id references work
-- Remove only if an incorrect constraint was created earlier
ALTER TABLE public.blood_requests 
DROP CONSTRAINT IF EXISTS blood_requests_hospital_id_fkey;



-- Add missing columns for dashboard functionality
ALTER TABLE public.donor_tracking ADD COLUMN IF NOT EXISTS current_lat DOUBLE PRECISION;
ALTER TABLE public.donor_tracking ADD COLUMN IF NOT EXISTS current_lon DOUBLE PRECISION;
ALTER TABLE public.donor_tracking ADD COLUMN IF NOT EXISTS last_updated TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Add hospital_id column to blood_requests (seems to be missing the reference)
UPDATE public.blood_requests SET hospital_id = requesting_hospital_id WHERE hospital_id IS NULL;

-- Add status column with proper values for request tracking
UPDATE public.blood_requests SET status = 'active' WHERE status IS NULL;

-- Enable real-time subscriptions on all tables (run these one by one)
ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.donor_responses;
ALTER PUBLICATION supabase_realtime ADD TABLE public.donor_tracking;
ALTER PUBLICATION supabase_realtime ADD TABLE public.blood_requests;

-- Add RLS policy for donor_tracking current location updates
CREATE POLICY "Allow donors to update their own tracking location"
ON public.donor_tracking FOR UPDATE
USING (auth.uid() = donor_id)
WITH CHECK (auth.uid() = donor_id);




-- Fix the trigger function for blood_requests
CREATE OR REPLACE FUNCTION update_blood_requests_geography()
RETURNS TRIGGER AS $$
BEGIN
  -- Get hospital location from profiles table and set it in the request
  SELECT latitude, longitude INTO NEW.latitude, NEW.longitude 
  FROM public.profiles 
  WHERE id = NEW.requesting_hospital_id;
  
  -- Only create geography point if we have valid coordinates
  IF NEW.longitude IS NOT NULL AND NEW.latitude IS NOT NULL THEN
    NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop old trigger and create new one
DROP TRIGGER IF EXISTS trigger_update_blood_requests_location ON public.blood_requests;
CREATE TRIGGER trigger_update_blood_requests_location
  BEFORE INSERT OR UPDATE ON public.blood_requests
  FOR EACH ROW EXECUTE FUNCTION update_blood_requests_geography();


-- Add missing latitude and longitude columns to blood_requests table
ALTER TABLE public.blood_requests 
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

-- Now update the trigger function to work correctly
CREATE OR REPLACE FUNCTION update_blood_requests_geography()
RETURNS TRIGGER AS $$
DECLARE
    hospital_lat DOUBLE PRECISION;
    hospital_lon DOUBLE PRECISION;
BEGIN
  -- Get hospital location from profiles table
  SELECT latitude, longitude INTO hospital_lat, hospital_lon 
  FROM public.profiles 
  WHERE id = NEW.requesting_hospital_id;
  
  -- Set the coordinates in the blood_requests record
  NEW.latitude = hospital_lat;
  NEW.longitude = hospital_lon;
  
  -- Only create geography point if we have valid coordinates
  IF NEW.longitude IS NOT NULL AND NEW.latitude IS NOT NULL THEN
    NEW.location = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update the trigger
DROP TRIGGER IF EXISTS trigger_update_blood_requests_location ON public.blood_requests;
CREATE TRIGGER trigger_update_blood_requests_location
  BEFORE INSERT OR UPDATE ON public.blood_requests
  FOR EACH ROW EXECUTE FUNCTION update_blood_requests_geography();


-- First, make sure hospital_id column exists and has the right values
UPDATE public.blood_requests 
SET hospital_id = requesting_hospital_id 
WHERE hospital_id IS NULL;

-- Drop any existing incorrect foreign key constraint
ALTER TABLE public.blood_requests 
DROP CONSTRAINT IF EXISTS blood_requests_hospital_id_fkey;

-- Add the correct foreign key constraint
ALTER TABLE public.blood_requests 
ADD CONSTRAINT blood_requests_hospital_id_fkey 
FOREIGN KEY (hospital_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Also ensure requesting_hospital_id has proper constraint
ALTER TABLE public.blood_requests 
DROP CONSTRAINT IF EXISTS blood_requests_requesting_hospital_id_fkey;

ALTER TABLE public.blood_requests 
ADD CONSTRAINT blood_requests_requesting_hospital_id_fkey 
FOREIGN KEY (requesting_hospital_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Add more detailed status tracking
ALTER TABLE public.donor_responses 
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Add status options: 'accepted', 'on_way', 'arrived', 'completed', 'cancelled'
ALTER TABLE public.donor_responses 
DROP CONSTRAINT IF EXISTS donor_responses_response_status_check;

ALTER TABLE public.donor_responses 
ADD CONSTRAINT donor_responses_response_status_check 
CHECK (response_status IN ('accepted', 'on_way', 'arrived', 'completed', 'cancelled'));

-- Function to handle donor status updates
CREATE OR REPLACE FUNCTION update_donor_status(
  response_id_param uuid,
  new_status text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Update donor response status
  UPDATE public.donor_responses 
  SET response_status = new_status, updated_at = NOW()
  WHERE id = response_id_param;
  
  -- If donor completed donation, check if request should be fulfilled
  IF new_status = 'completed' THEN
    -- Get the request details
    UPDATE public.blood_requests 
    SET status = 'fulfilled'
    WHERE id = (
      SELECT request_id FROM public.donor_responses WHERE id = response_id_param
    )
    AND (
      -- Check if enough donors have completed
      SELECT COUNT(*) FROM public.donor_responses dr 
      WHERE dr.request_id = (
        SELECT request_id FROM public.donor_responses WHERE id = response_id_param
      ) 
      AND dr.response_status = 'completed'
    ) >= (
      SELECT units_required FROM public.blood_requests br
      WHERE br.id = (
        SELECT request_id FROM public.donor_responses WHERE id = response_id_param
      )
    );
  END IF;
  
  -- If donor cancelled, remove from tracking
  IF new_status = 'cancelled' THEN
    DELETE FROM public.donor_tracking 
    WHERE response_id = response_id_param;
  END IF;
END;
$$;

-- Function for hospitals to mark request as fulfilled
CREATE OR REPLACE FUNCTION mark_request_fulfilled(request_id_param uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only allow hospital that created the request to mark as fulfilled
  UPDATE public.blood_requests 
  SET status = 'fulfilled', updated_at = NOW()
  WHERE id = request_id_param 
  AND requesting_hospital_id = auth.uid();
  
  -- Clean up tracking for this request
  DELETE FROM public.donor_tracking 
  WHERE request_id = request_id_param;
END;
$$;

-- Add RLS policies for the new functions
CREATE POLICY "Allow donors to update their own response status"
ON public.donor_responses FOR UPDATE
USING (auth.uid() = donor_id)
WITH CHECK (auth.uid() = donor_id);




-- Clean up redundant columns and ensure data consistency
-- Run this after backing up your data

-- 1. Ensure hospital_id matches requesting_hospital_id
UPDATE public.blood_requests 
SET hospital_id = requesting_hospital_id 
WHERE hospital_id IS NULL OR hospital_id != requesting_hospital_id;

-- 2. Consider removing redundant column (after confirming all references use requesting_hospital_id)
-- ALTER TABLE public.blood_requests DROP COLUMN IF EXISTS hospital_id;

-- 3. Fix potential null location issues in triggers
CREATE OR REPLACE FUNCTION update_blood_requests_geography()
RETURNS TRIGGER AS $$
DECLARE
    hospital_lat DOUBLE PRECISION;
    hospital_lon DOUBLE PRECISION;
BEGIN
  -- Get hospital location from profiles table
  SELECT latitude, longitude INTO hospital_lat, hospital_lon 
  FROM public.profiles 
  WHERE id = NEW.requesting_hospital_id;
  
  -- Only update if we have valid coordinates
  IF hospital_lat IS NOT NULL AND hospital_lon IS NOT NULL THEN
    NEW.latitude = hospital_lat;
    NEW.longitude = hospital_lon;
    NEW.location = ST_SetSRID(ST_MakePoint(hospital_lon, hospital_lat), 4326)::geography;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Add index for better performance on location queries
CREATE INDEX IF NOT EXISTS idx_profiles_location ON public.profiles USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_blood_requests_location ON public.blood_requests USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_profiles_blood_type ON public.profiles (blood_type) WHERE role = 'donor';


CREATE OR REPLACE FUNCTION mark_request_fulfilled(request_id_param UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE blood_requests 
  SET 
    status = 'fulfilled',
    fulfilled_at = NOW()
  WHERE id = request_id_param;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Request not found';
  END IF;
END;
$$;
ALTER TABLE public.blood_requests 
ADD COLUMN fulfilled_at TIMESTAMP WITH TIME ZONE;


-- Replace the existing function with corrected blood compatibility
-- CREATE OR REPLACE FUNCTION public.match_donors_and_notify_ai(
--   request_id_param uuid,
--   blood_type_param text,
--   initial_radius_km numeric DEFAULT 10.0,
--   max_donors_to_notify integer DEFAULT 10
-- )
-- RETURNS void
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- AS $$
-- DECLARE
--   request_record record;
--   donor_record record;
--   hospital_record record;
--   search_radius_m numeric;
--   urgency_level text := 'normal';
--   compatible_blood_types text[];
-- BEGIN
--   -- Get request and hospital details
--   SELECT * INTO request_record FROM public.blood_requests WHERE id = request_id_param;
--   SELECT * INTO hospital_record FROM public.profiles WHERE id = request_record.requesting_hospital_id;
  
--   search_radius_m := initial_radius_km * 1000;
  
--   -- FIXED: Correct blood compatibility matrix
--   compatible_blood_types := CASE blood_type_param
--     WHEN 'A+' THEN ARRAY['A+', 'A-', 'O+', 'O-']
--     WHEN 'A-' THEN ARRAY['A-', 'O-']
--     WHEN 'B+' THEN ARRAY['B+', 'B-', 'O+', 'O-']
--     WHEN 'B-' THEN ARRAY['B-', 'O-']
--     WHEN 'AB+' THEN ARRAY['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'] -- Universal recipient
--     WHEN 'AB-' THEN ARRAY['A-', 'B-', 'AB-', 'O-']
--     WHEN 'O+' THEN ARRAY['O+', 'O-']
--     WHEN 'O-' THEN ARRAY['O-'] -- Can only receive O-
--     ELSE ARRAY[blood_type_param] -- Fallback
--   END;
  
--   -- Determine urgency based on blood type and units
--   IF blood_type_param IN ('O-', 'AB-') OR request_record.units_required >= 4 THEN
--     urgency_level := 'critical';
--     max_donors_to_notify := max_donors_to_notify * 2;
--   END IF;
  
--   -- Find and prioritize compatible donors using AI scoring
--   FOR donor_record IN
--     WITH scored_donors AS (
--       SELECT 
--         p.id,
--         p.full_name,
--         p.phone,
--         p.blood_type,
--         p.latitude,
--         p.longitude,
--         -- Use existing AI scoring system
--         calculate_donor_availability_score(p.id, urgency_level) as ai_score,
--         -- Calculate distance
--         (
--           6371000 * acos(
--             cos(radians(hospital_record.latitude)) * 
--             cos(radians(p.latitude)) * 
--             cos(radians(p.longitude) - radians(hospital_record.longitude)) + 
--             sin(radians(hospital_record.latitude)) * 
--             sin(radians(p.latitude))
--           )
--         ) as distance_m,
--         -- Add reliability factor
--         COALESCE(p.reliability_score, 0.5) as reliability,
--         -- Add response speed factor  
--         CASE 
--           WHEN p.average_response_time_minutes <= 10 THEN 1.0
--           WHEN p.average_response_time_minutes <= 30 THEN 0.8
--           ELSE 0.6
--         END as speed_factor
--       FROM public.profiles p
--       WHERE 
--         p.role = 'donor' 
--         AND p.blood_type = ANY(compatible_blood_types) -- FIXED: Use compatibility array
--         AND p.latitude IS NOT NULL 
--         AND p.longitude IS NOT NULL
--         AND NOT EXISTS (
--           SELECT 1 FROM public.notifications n 
--           WHERE n.donor_id = p.id AND n.request_id = request_id_param
--         )
--     )
--     SELECT * FROM scored_donors 
--     WHERE distance_m <= search_radius_m
--     ORDER BY 
--       -- Enhanced multi-factor scoring
--       (ai_score * 0.4 + reliability * 0.3 + speed_factor * 0.2 + (1 - distance_m/search_radius_m) * 0.1) DESC,
--       distance_m ASC
--     LIMIT max_donors_to_notify
--   LOOP
--     -- Create notification
--     INSERT INTO public.notifications (request_id, donor_id, status)
--     VALUES (request_id_param, donor_record.id, 'pending')
--     ON CONFLICT (request_id, donor_id) DO NOTHING;
--   END LOOP;
  
--   -- Log AI matching results
--   RAISE NOTICE 'AI matching completed for request % with % compatible blood types', 
--     request_id_param, array_length(compatible_blood_types, 1);
-- END;
-- $$;
CREATE OR REPLACE FUNCTION public.match_donors_and_notify_ai(
  request_id_param uuid,
  blood_type_param text,
  initial_radius_km numeric DEFAULT 10.0,
  max_donors_to_notify integer DEFAULT 10
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  request_record record;
  donor_record record;
  hospital_record record;
  search_radius_m numeric;
  urgency_level text := 'normal';
  compatible_blood_types text[];
BEGIN
  -- Get request and hospital details
  SELECT * INTO request_record FROM public.blood_requests WHERE id = request_id_param;
  SELECT * INTO hospital_record FROM public.profiles WHERE id = request_record.requesting_hospital_id;
  
  -- Debug: Check if hospital record is found
  IF hospital_record IS NULL THEN
    RAISE NOTICE 'Hospital not found for request %', request_id_param;
    RETURN;
  END IF;
  
  -- Debug: Check hospital location
  IF hospital_record.latitude IS NULL OR hospital_record.longitude IS NULL THEN
    RAISE NOTICE 'Hospital location missing (lat: %, lon: %)', 
      hospital_record.latitude, hospital_record.longitude;
    RETURN;
  END IF;
  
  search_radius_m := initial_radius_km * 1000;
  
  -- FIXED: Correct blood compatibility matrix
  compatible_blood_types := CASE blood_type_param
    WHEN 'A+' THEN ARRAY['A+', 'A-', 'O+', 'O-']
    WHEN 'A-' THEN ARRAY['A-', 'O-']
    WHEN 'B+' THEN ARRAY['B+', 'B-', 'O+', 'O-']
    WHEN 'B-' THEN ARRAY['B-', 'O-']
    WHEN 'AB+' THEN ARRAY['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
    WHEN 'AB-' THEN ARRAY['A-', 'B-', 'AB-', 'O-']
    WHEN 'O+' THEN ARRAY['O+', 'O-']
    WHEN 'O-' THEN ARRAY['O-']
    ELSE ARRAY[blood_type_param]
  END;
  
  -- Debug: Log compatible blood types
  RAISE NOTICE 'Compatible blood types for %: %', blood_type_param, compatible_blood_types;
  
  -- Determine urgency based on blood type and units
  IF blood_type_param IN ('O-', 'AB-') OR request_record.units_required >= 4 THEN
    urgency_level := 'critical';
    max_donors_to_notify := max_donors_to_notify * 2;
  END IF;
  
  -- Find and prioritize compatible donors using AI scoring
  FOR donor_record IN
    WITH scored_donors AS (
      SELECT 
        p.id,
        p.full_name,
        p.phone,
        p.blood_type,
        p.latitude,
        p.longitude,
        -- Use existing AI scoring system
        COALESCE(calculate_donor_availability_score(p.id, urgency_level), 0.5) as ai_score,
        -- Calculate distance
        (
          6371000 * acos(
            cos(radians(hospital_record.latitude)) * 
            cos(radians(p.latitude)) * 
            cos(radians(p.longitude) - radians(hospital_record.longitude)) + 
            sin(radians(hospital_record.latitude)) * 
            sin(radians(p.latitude))
          )
        ) as distance_m,
        -- Add reliability factor
        COALESCE(p.reliability_score, 0.5) as reliability,
        -- Add response speed factor  
        CASE 
          WHEN p.average_response_time_minutes <= 10 THEN 1.0
          WHEN p.average_response_time_minutes <= 30 THEN 0.8
          ELSE 0.6
        END as speed_factor
      FROM public.profiles p
      WHERE 
        p.role = 'donor' 
        AND p.blood_type = ANY(compatible_blood_types)
        AND p.latitude IS NOT NULL 
        AND p.longitude IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.notifications n 
          WHERE n.donor_id = p.id AND n.request_id = request_id_param
        )
    )
    SELECT * FROM scored_donors 
    WHERE distance_m <= search_radius_m
    ORDER BY 
      -- Enhanced multi-factor scoring
      (ai_score * 0.4 + reliability * 0.3 + speed_factor * 0.2 + (1 - distance_m/search_radius_m) * 0.1) DESC,
      distance_m ASC
    LIMIT max_donors_to_notify
  LOOP
    -- Debug: Log matched donor
    RAISE NOTICE 'Matched donor % (blood type: %, distance: %m, score: %)', 
      donor_record.id, 
      donor_record.blood_type, 
      ROUND(donor_record.distance_m::numeric, 1),
      ROUND((donor_record.ai_score * 0.4 + donor_record.reliability * 0.3 + 
             donor_record.speed_factor * 0.2 + 
             (1 - donor_record.distance_m/search_radius_m) * 0.1)::numeric, 3);
    
    -- Create notification
    INSERT INTO public.notifications (request_id, donor_id, status)
    VALUES (request_id_param, donor_record.id, 'pending')
    ON CONFLICT (request_id, donor_id) DO NOTHING;
  END LOOP;
  
  -- Log AI matching results
  RAISE NOTICE 'AI matching completed for request % with urgency %', 
    request_id_param, urgency_level;
END;
$$;

-- Add function to determine optimal notification time
CREATE OR REPLACE FUNCTION should_notify_donor_now(
  donor_id_param uuid,
  urgency_level text DEFAULT 'normal'
)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
  current_hour integer;
  donor_profile record;
BEGIN
  current_hour := EXTRACT(HOUR FROM NOW());
  
  -- Always notify for critical requests
  IF urgency_level = 'critical' THEN
    RETURN true;
  END IF;
  
  -- Avoid notifications during sleep hours (11 PM - 6 AM) unless urgent
  IF current_hour >= 23 OR current_hour < 6 THEN
    RETURN urgency_level = 'urgent';
  END IF;
  
  -- Get donor's preferred times (if available)
  SELECT * INTO donor_profile FROM public.profiles WHERE id = donor_id_param;
  
  -- Check if donor has been responsive during current time
  IF donor_profile.last_response_time IS NOT NULL THEN
    -- If they responded during similar hours, they're likely available
    RETURN EXTRACT(HOUR FROM donor_profile.last_response_time) BETWEEN current_hour-2 AND current_hour+2;
  END IF;
  
  -- Default to business hours being optimal
  RETURN current_hour BETWEEN 9 AND 20;
END;
$$;


-- Add function to expand search if not enough donors found
CREATE OR REPLACE FUNCTION expand_search_if_needed(
  request_id_param uuid,
  blood_type_param text,
  current_radius_km numeric
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  notification_count integer;
  required_donors integer;
BEGIN
  -- Count current notifications
  SELECT COUNT(*) INTO notification_count 
  FROM public.notifications 
  WHERE request_id = request_id_param;
  
  -- Determine required minimum based on blood type
  required_donors := CASE 
    WHEN blood_type_param IN ('O-', 'AB-') THEN 5
    ELSE 3
  END;
  
  -- If not enough donors, expand search
  IF notification_count < required_donors THEN
    PERFORM match_donors_and_notify_ai(
      request_id_param, 
      blood_type_param, 
      current_radius_km * 1.5, -- Expand radius by 50%
      10 -- Additional donors to notify
    );
  END IF;
END;
$$;



-- Add this function for emergency expansion
CREATE OR REPLACE FUNCTION expand_search_if_needed(
  request_id_param uuid,
  blood_type_param text,
  current_radius_km numeric
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  notification_count integer;
  required_donors integer;
BEGIN
  SELECT COUNT(*) INTO notification_count 
  FROM public.notifications 
  WHERE request_id = request_id_param;
  
  required_donors := CASE 
    WHEN blood_type_param IN ('O-', 'AB-') THEN 5
    ELSE 3
  END;
  
  IF notification_count < required_donors THEN
    PERFORM match_donors_and_notify_ai(
      request_id_param, 
      blood_type_param, 
      current_radius_km * 1.5,
      10
    );
  END IF;
END;
$$;

ALTER TABLE public.blood_requests 
   ADD COLUMN IF NOT EXISTS urgency_level TEXT DEFAULT 'normal';


ALTER TABLE donor_tracking ADD COLUMN speed REAL;
ALTER TABLE donor_tracking ADD COLUMN heading REAL;
ALTER TABLE donor_tracking ADD COLUMN accuracy REAL;
ALTER TABLE donor_tracking ADD COLUMN altitude REAL;

ALTER TABLE profiles ADD COLUMN last_seen TIMESTAMPTZ;


