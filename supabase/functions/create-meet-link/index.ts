import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? 'https://rfoykeibwxosxpxlqlfc.supabase.co'
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

serve(async (req) => {
  const { agent_id, buyer_id, property_id, scheduled_time } = await req.json()
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  
  const meetingId = crypto.randomUUID()
  const meet_link = `https://meet.google.com/${meetingId.substring(0, 10)}`
  
  const { data: booking } = await supabase.from('virtual_tour_bookings').insert({
    property_id,
    agent_id,
    buyer_id,
    meet_link,
    scheduled_for: scheduled_time,
    status: 'scheduled'
  }).select().single()
  
  await supabase.from('notifications').insert([
    {
      user_id: agent_id,
      notification_type: 'listing_viewed',
      title: 'Virtual Tour Scheduled',
      body: `A buyer has scheduled a virtual tour for ${new Date(scheduled_time).toLocaleString()}`,
      metadata: { booking_id: booking.id, meet_link }
    },
    {
      user_id: buyer_id,
      notification_type: 'listing_viewed',
      title: 'Virtual Tour Scheduled',
      body: `Your virtual tour is scheduled for ${new Date(scheduled_time).toLocaleString()}. Click to join: ${meet_link}`,
      metadata: { booking_id: booking.id, meet_link }
    }
  ])
  
  return new Response(JSON.stringify({ meet_link, booking_id: booking.id, join_url: meet_link }), { headers: { 'Content-Type': 'application/json' } })
})
