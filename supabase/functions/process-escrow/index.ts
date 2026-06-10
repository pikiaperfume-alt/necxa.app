import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = 'https://rfoykeibwxosxpxlqlfc.supabase.co'
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''

serve(async (req) => {
  const { property_id, buyer_id } = await req.json()
  
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  
  // Call the database function
  const { data, error } = await supabase.rpc('process_escrow_reservation', {
    p_property_id: property_id,
    p_buyer_id: buyer_id
  })
  
  if (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    )
  }
  
  return new Response(
    JSON.stringify(data?.[0] || { success: false }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
