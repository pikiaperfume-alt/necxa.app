import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { initiateMTNPayment, initiateAirtelPayment } from '../_shared/payments.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { listing_id, buyer_phone, method, amount, buyer_id, buyer_email } = await req.json()

    // 1. For NCX_COINS, process immediately via RPC
    if (method === 'NCX_COINS') {
      const { data: unlockData, error: unlockError } = await supabaseClient.rpc('process_unlock', {
        p_property_id: listing_id,
        p_buyer_id: buyer_id
      })
      if (unlockError) throw unlockError
      
      return new Response(JSON.stringify({ 
        success: true, 
        message: 'NCX Unlock successful',
        data: unlockData 
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 2. For MoMo/Airtel, create a pending unlock record
    const { data: unlock, error: insertError } = await supabaseClient
      .from('listing_unlocks')
      .insert({
        listing_id,
        buyer_agent_id: buyer_id,
        buyer_email,
        buyer_phone,
        amount_ugx: amount,
        payment_method: method,
        payment_status: 'PENDING'
      })
      .select()
      .single()

    if (insertError) throw insertError

    // 3. Initiate External Payment via MoMo/Airtel
    let externalRes;
    if (method === 'MTN_MOMO') {
      externalRes = await initiateMTNPayment({
        amount: Number(amount),
        phone: buyer_phone,
        externalId: unlock.id,
        description: `NECXA Unlock Listing ${listing_id}`
      })
    } else {
      externalRes = await initiateAirtelPayment({
        amount: Number(amount),
        phone: buyer_phone,
        reference: unlock.id
      })
    }

    return new Response(JSON.stringify({ 
      success: true, 
      payment_id: unlock.id,
      external_ref: externalRes
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
