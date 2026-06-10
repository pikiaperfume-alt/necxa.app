import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'

serve(async (req) => {
  const { to_number, message } = await req.json()
  
  // Basic formatting for East Africa
  let formattedNumber = to_number.replace(/\D/g, '')
  if (formattedNumber.startsWith('0')) {
    formattedNumber = '256' + formattedNumber.substring(1)
  }
  if (!formattedNumber.startsWith('256')) {
    formattedNumber = '256' + formattedNumber
  }
  
  // Integration Placeholder for WhatsApp Business API
  // In production, use Twilio, Meta API, or a specialized microservice.
  console.log(`WhatsApp message would be sent to ${formattedNumber}: ${message}`)
  
  return new Response(
    JSON.stringify({ 
      success: true, 
      message: `WhatsApp message ready to send to +${formattedNumber}`,
      note: "WhatsApp Business API integration required for production"
    }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
