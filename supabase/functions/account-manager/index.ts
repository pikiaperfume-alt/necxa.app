import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// ============================================
// ACCOUNT-MANAGER — User Lifecycle & Security
// ============================================

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })

const err = (msg: string, status = 400) => json({ error: msg }, status)

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { autoRefreshToken: false, persistSession: false } }
)

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders })

  try {
    const { action, user_id } = await req.json()

    if (!user_id) return err("user_id required")

    // ── 1. REQUEST DELETION ──
    if (action === "request-deletion") {
      const deletionDate = new Date()
      deletionDate.setDate(deletionDate.getDate() + 14) // 14-day cooling period

      const { error } = await supabase
        .from("profiles")
        .update({ 
          scheduled_deletion_at: deletionDate.toISOString(), 
          status: "deleting" 
        })
        .eq("id", user_id)

      if (error) {
        console.error("Deletion error:", error.message)
        return err(`Account deletion request failed: ${error.message}`)
      }

      return json({ 
        success: true, 
        message: "Account scheduled for deletion in 14 days.",
        deletion_date: deletionDate.toISOString() 
      })
    }

    // ── 2. CANCEL DELETION ──
    if (action === "cancel-deletion") {
      const { error } = await supabase
        .from("profiles")
        .update({ 
          scheduled_deletion_at: null, 
          status: "active" 
        })
        .eq("id", user_id)

      if (error) return err(`Failed to cancel deletion: ${error.message}`)
      return json({ success: true, message: "Account deletion cancelled." })
    }

    return err("Invalid action. Supported: request-deletion, cancel-deletion")

  } catch (error: unknown) {
    const msg = error instanceof Error ? error.message : String(error)
    console.error("Account Manager Error:", msg)
    return err(`Server error: ${msg}`, 500)
  }
})
