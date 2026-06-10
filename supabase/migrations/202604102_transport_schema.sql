-- NECXA TRANSPORT SYSTEM MIGRATION
-- Version: 1.0 (Logistics Marketplace)

-- 1. DRIVERS TABLE
CREATE TABLE IF NOT EXISTS public.transport_drivers (
    id UUID PRIMARY KEY REFERENCES auth.users(id),
    name TEXT NOT NULL,
    email TEXT,
    phone TEXT,
    number_plate TEXT UNIQUE NOT NULL,
    vehicle_type TEXT CHECK (vehicle_type IN ('bike', 'van', 'truck')),
    permit_url TEXT,
    is_verified BOOLEAN DEFAULT FALSE,
    is_available BOOLEAN DEFAULT TRUE,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. ORDERS TABLE
CREATE TABLE IF NOT EXISTS public.transport_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) NOT NULL,
    driver_id UUID REFERENCES public.transport_drivers(id),
    pickup_location TEXT NOT NULL,
    dropoff_location TEXT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'inProgress', 'completed', 'cancelled')),
    price DECIMAL(12, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 3. RLS POLICIES
ALTER TABLE public.transport_drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transport_orders ENABLE ROW LEVEL SECURITY;

-- Drivers: Anyone can view available drivers, only owner can update their profile.
CREATE POLICY "Drivers are viewable by everyone" ON public.transport_drivers
    FOR SELECT USING (is_available = true OR auth.uid() = id);

CREATE POLICY "Drivers can update their own data" ON public.transport_drivers
    FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Drivers can insert their own data" ON public.transport_drivers
    FOR INSERT WITH CHECK (auth.uid() = id);

-- Orders: Users can view their own orders, drivers can view orders assigned to them or pending ones.
CREATE POLICY "Users can view their own orders" ON public.transport_orders
    FOR SELECT USING (auth.uid() = user_id OR auth.uid() = driver_id);

CREATE POLICY "Users can create orders" ON public.transport_orders
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Drivers can update orders assigned to them" ON public.transport_orders
    FOR UPDATE USING (auth.uid() = driver_id OR status = 'pending');

-- 4. PERFORMANCE INDEXES
CREATE INDEX IF NOT EXISTS idx_drivers_geo ON public.transport_drivers(lat, lng);
CREATE INDEX IF NOT EXISTS idx_drivers_available ON public.transport_drivers(is_available, is_verified);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.transport_orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.transport_orders(status);
