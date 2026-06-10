import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? 'https://rfoykeibwxosxpxlqlfc.supabase.co'
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

serve(async (req) => {
  const { property_id, buyer_id, unlock_transaction_id } = await req.json()
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  
  const { data: property } = await supabase.from('properties').select('*, profiles:lister_id(*), agent_contact_methods(*)').eq('id', property_id).single()
  
  const { data: existing } = await supabase.from('chat_conversations').select('id').eq('property_id', property_id).eq('buyer_id', buyer_id).maybeSingle()
  if (existing) {
    return new Response(JSON.stringify({ conversation_id: existing.id }), { headers: { 'Content-Type': 'application/json' } })
  }
  
  const { data: conversation } = await supabase.from('chat_conversations').insert({
    property_id,
    buyer_id,
    seller_id: property.lister_id,
    agent_id: property.agent_id,
    unlocked_by_buyer: true,
    unlocked_at: new Date().toISOString(),
    unlock_transaction_id
  }).select().single()
  
  await supabase.from('in_app_chat_messages').insert({
    conversation_id: conversation.id,
    property_id,
    sender_id: null,
    receiver_id: buyer_id,
    message: `You have successfully unlocked this property. You can now chat with the agent/lister.`,
    is_system_message: true
  })
  
  await supabase.from('notifications').insert({
    user_id: property.agent_id || property.lister_id,
    notification_type: 'new_message',
    title: 'New Listing Inquiry',
    body: `A verified buyer has unlocked your profile and can now message you about ${property.title}.`,
    metadata: { property_id, conversation_id: conversation.id }
  })
  
  return new Response(JSON.stringify({ conversation_id: conversation.id }), { headers: { 'Content-Type': 'application/json' } })
})
