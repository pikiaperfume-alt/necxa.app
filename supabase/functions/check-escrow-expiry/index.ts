import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = 'https://rfoykeibwxosxpxlqlfc.supabase.co'
const SUPABASE_ANON_KEY = 'sb_publishable_0l37RUnk-RZSvFZk-RbR0g_nEPY8rLu'

serve(async (req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
    
    const { data: expired, error: fetchError } = await supabase
      .from('escrow_reservations')
      .select('id, property_id, buyer_id, deposit_amount')
      .eq('status', 'pending')
      .lt('reservation_expires_at', new Date().toISOString())
    
    if (fetchError) {
      return new Response(
        JSON.stringify({ error: fetchError.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    if (!expired || expired.length === 0) {
      return new Response(
        JSON.stringify({ success: true, message: 'No expired escrows' }),
        { headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    const expiredIds = expired.map(e => e.id)
    
    await supabase
      .from('escrow_reservations')
      .update({ status: 'expired' })
      .in('id', expiredIds)
    
    for (const reservation of expired) {
      const { data: buyerWallet } = await supabase
        .from('wallets')
        .select('id, fiat_balance, escrow_balance')
        .eq('user_id', reservation.buyer_id)
        .single()
      
      if (buyerWallet) {
        await supabase
          .from('wallets')
          .update({
            fiat_balance: buyerWallet.fiat_balance + reservation.deposit_amount,
            escrow_balance: buyerWallet.escrow_balance - reservation.deposit_amount,
            updated_at: new Date().toISOString()
          })
          .eq('id', buyerWallet.id)
      }
      
      await supabase
        .from('properties')
        .update({
          escrow_status: 'available',
          active_escrow_tx_id: null,
          escrow_timestamp: null,
          escrow_expires_at: null
        })
        .eq('id', reservation.property_id)
      
      await supabase
        .from('notifications')
        .insert({
          user_id: reservation.buyer_id,
          notification_type: 'escrow_expired',
          title: 'Reservation Expired',
          body: 'Your reservation has expired. The property has been relisted.',
          metadata: { property_id: reservation.property_id, escrow_id: reservation.id },
          is_sent: true,
          sent_at: new Date().toISOString()
        })
    }
    
    return new Response(
      JSON.stringify({ success: true, expired_count: expired.length }),
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
