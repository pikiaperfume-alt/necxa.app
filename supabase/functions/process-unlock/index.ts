import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = 'https://rfoykeibwxosxpxlqlfc.supabase.co'
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY') ?? ''

serve(async (req) => {
  const { property_id, buyer_id } = await req.json()
  
  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  
  // Call the database function
  const { data, error } = await supabase.rpc('process_unlock', {
    p_property_id: property_id,
    p_buyer_id: buyer_id
  })
  
  if (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    )
  }
  
  // If unlock successful, get property details to return
  if (data && data[0]?.success) {
    const { data: property } = await supabase
      .from('properties')
      .select('latitude, longitude, address, agent_id')
      .eq('id', property_id)
      .single()
    
    const { data: agentContact } = await supabase
      .from('agent_contact_methods')
      .select('*')
      .eq('agent_id', property?.agent_id)
      .single()
    
    return new Response(
      JSON.stringify({
        success: true,
        unlock_id: data[0]?.unlock_id,
        property: {
          latitude: property?.latitude,
          longitude: property?.longitude,
          address: property?.address
        },
        agent_contact: agentContact
      }),
      { headers: { 'Content-Type': 'application/json' } }
    )
  }
  
  return new Response(
    JSON.stringify(data?.[0] || { success: false, message: 'Unknown error' }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
