import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = 'https://rfoykeibwxosxpxlqlfc.supabase.co'
const SUPABASE_ANON_KEY = 'sb_publishable_0l37RUnk-RZSvFZk-RbR0g_nEPY8rLu'

function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000
  const phi1 = lat1 * Math.PI / 180
  const phi2 = lat2 * Math.PI / 180
  const deltaPhi = (lat2 - lat1) * Math.PI / 180
  const deltaLambda = (lon2 - lon1) * Math.PI / 180

  const a = Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
            Math.cos(phi1) * Math.cos(phi2) *
            Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2)
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

  return R * c
}

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'Method not allowed' }),
        { status: 405, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const body = await req.json()
    const escrow_id = body.escrow_id
    const buyer_id = body.buyer_id
    const latitude = body.latitude
    const longitude = body.longitude
    
    if (!escrow_id || !buyer_id) {
      return new Response(
        JSON.stringify({ error: 'escrow_id and buyer_id are required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    if (!latitude || !longitude) {
      return new Response(
        JSON.stringify({ error: 'latitude and longitude are required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
    
    const { data: escrow, error: escrowError } = await supabase
      .from('escrow_reservations')
      .select('*, property:property_id(*)')
      .eq('id', escrow_id)
      .eq('buyer_id', buyer_id)
      .eq('status', 'pending')
      .single()
    
    if (escrowError || !escrow) {
      return new Response(
        JSON.stringify({ error: 'Escrow not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    const { data: property } = await supabase
      .from('properties')
      .select('latitude, longitude, title, lister_id, agent_id, price')
      .eq('id', escrow.property_id)
      .single()
    
    if (!property) {
      return new Response(
        JSON.stringify({ error: 'Property not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    const distance = calculateDistance(latitude, longitude, property.latitude, property.longitude)
    
    if (distance > 100) {
      return new Response(
        JSON.stringify({ 
          error: `Must be within 100m of property. Distance: ${Math.round(distance)}m` 
        }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    const agentCommission = Math.floor(property.price * 0.05)
    const netToSeller = escrow.deposit_amount
    
    const { data: buyerWallet } = await supabase
      .from('wallets')
      .select('id')
      .eq('user_id', buyer_id)
      .single()
    
    const { data: sellerWallet } = await supabase
      .from('wallets')
      .select('id, fiat_balance')
      .eq('user_id', property.lister_id)
      .single()
    
    await supabase
      .from('escrow_reservations')
      .update({
        status: 'completed',
        deposit_released_at: new Date().toISOString(),
        qr_scanned_at: new Date().toISOString(),
        qr_scanned_latitude: latitude,
        qr_scanned_longitude: longitude
      })
      .eq('id', escrow_id)
    
    if (sellerWallet) {
      await supabase
        .from('wallets')
        .update({
          fiat_balance: sellerWallet.fiat_balance + netToSeller,
          updated_at: new Date().toISOString()
        })
        .eq('id', sellerWallet.id)
    }
    
    if (buyerWallet) {
      await supabase
        .from('wallets')
        .update({
          escrow_balance: 0,
          updated_at: new Date().toISOString()
        })
        .eq('id', buyerWallet.id)
    }
    
    if (escrow.agent_id) {
      const { data: agentWallet } = await supabase
        .from('wallets')
        .select('id, fiat_balance')
        .eq('user_id', escrow.agent_id)
        .single()
      
      if (agentWallet) {
        await supabase
          .from('wallets')
          .update({
            fiat_balance: agentWallet.fiat_balance + agentCommission,
            updated_at: new Date().toISOString()
          })
          .eq('id', agentWallet.id)
      }
    }
    
    await supabase
      .from('properties')
      .update({
        escrow_status: 'sold',
        is_active: false,
        is_sold: true,
        sold_at: new Date().toISOString(),
        final_buyer_id: buyer_id
      })
      .eq('id', escrow.property_id)
    
    await supabase
      .from('notifications')
      .insert([
        {
          user_id: property.lister_id,
          notification_type: 'escrow_completed',
          title: 'Sale Completed',
          body: `Your property has been successfully sold.`,
          metadata: { property_id: escrow.property_id, escrow_id, buyer_id },
          is_sent: true,
          sent_at: new Date().toISOString()
        },
        {
          user_id: buyer_id,
          notification_type: 'escrow_completed',
          title: 'Reservation Completed',
          body: `You have successfully completed the reservation.`,
          metadata: { property_id: escrow.property_id, escrow_id },
          is_sent: true,
          sent_at: new Date().toISOString()
        }
      ])
    
    return new Response(
      JSON.stringify({
        success: true,
        agent_commission: agentCommission,
        distance_verified: Math.round(distance)
      }),
      { headers: { 'Content-Type': 'application/json' } }
    )
    
  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
