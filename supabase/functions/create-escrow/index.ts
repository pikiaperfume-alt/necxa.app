import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = 'https://rfoykeibwxosxpxlqlfc.supabase.co'
const SUPABASE_ANON_KEY = 'sb_publishable_0l37RUnk-RZSvFZk-RbR0g_nEPY8rLu'

serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return new Response(
        JSON.stringify({ error: 'Method not allowed' }),
        { status: 405, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const body = await req.json()
    const property_id = body.property_id
    const buyer_id = body.buyer_id
    
    if (!property_id || !buyer_id) {
      return new Response(
        JSON.stringify({ error: 'property_id and buyer_id are required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
    
    const { data: property, error: propertyError } = await supabase
      .from('properties')
      .select('id, price, lister_id, agent_id, title, is_active, escrow_status')
      .eq('id', property_id)
      .single()
    
    if (propertyError || !property) {
      return new Response(
        JSON.stringify({ error: 'Property not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    if (!property.is_active || property.escrow_status !== 'available') {
      return new Response(
        JSON.stringify({ error: 'Property is not available for reservation' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    const escrowDeposit = Math.floor(property.price * 0.1)
    const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString()
    
    const { data: wallet, error: walletError } = await supabase
      .from('wallets')
      .select('id, fiat_balance, escrow_balance')
      .eq('user_id', buyer_id)
      .single()
    
    if (walletError || !wallet) {
      return new Response(
        JSON.stringify({ error: 'Wallet not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    if (wallet.fiat_balance < escrowDeposit) {
      return new Response(
        JSON.stringify({ 
          error: 'Insufficient funds', 
          required: escrowDeposit, 
          balance: wallet.fiat_balance 
        }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    const qrCode = crypto.randomUUID().replace(/-/g, '').substring(0, 32)
    
    const newFiatBalance = wallet.fiat_balance - escrowDeposit
    const newEscrowBalance = wallet.escrow_balance + escrowDeposit
    
    const { error: updateError } = await supabase
      .from('wallets')
      .update({ 
        fiat_balance: newFiatBalance,
        escrow_balance: newEscrowBalance,
        updated_at: new Date().toISOString()
      })
      .eq('id', wallet.id)
    
    if (updateError) {
      return new Response(
        JSON.stringify({ error: 'Failed to update wallet' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    const { data: escrow, error: escrowError } = await supabase
      .from('escrow_reservations')
      .insert({
        property_id,
        buyer_id,
        seller_id: property.lister_id,
        agent_id: property.agent_id,
        property_value: property.price,
        deposit_amount: escrowDeposit,
        status: 'pending',
        deposit_paid_at: new Date().toISOString(),
        reservation_expires_at: expiresAt,
        qr_code: qrCode
      })
      .select()
      .single()
    
    // Wait, let's fix the logic that was incorrect in the paste. He had an update wallet logic inside escrowError block which is good for rollback.
    if (escrowError) {
      await supabase
        .from('wallets')
        .update({ 
          fiat_balance: wallet.fiat_balance,
          escrow_balance: wallet.escrow_balance
        })
        .eq('id', wallet.id)
      
      return new Response(
        JSON.stringify({ error: 'Failed to create escrow' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }
    
    await supabase
      .from('properties')
      .update({
        escrow_status: 'pending_escrow',
        escrow_timestamp: new Date().toISOString(),
        escrow_expires_at: expiresAt,
        active_escrow_tx_id: escrow.id
      })
      .eq('id', property_id)
    
    await supabase
      .from('notifications')
      .insert({
        user_id: property.lister_id,
        notification_type: 'escrow_created',
        title: 'Property Reserved',
        body: `Your property has been reserved with a ${escrowDeposit.toLocaleString()} UGX deposit.`,
        metadata: { property_id, escrow_id: escrow.id, buyer_id, expires_at: expiresAt },
        is_sent: true,
        sent_at: new Date().toISOString()
      })
    
    return new Response(
      JSON.stringify({
        success: true,
        escrow_id: escrow.id,
        expires_at: expiresAt,
        qr_code: qrCode
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
