import os

file_path = r"c:\Users\KNEST\.gemini\antigravity\scratch\necxa_flutter\lib\services\ai_service.dart"

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Remove _aiClient
ai_client_code = """  // ── SECONDARY SUPABASE CLIENT FOR DECOUPLED AI SERVICES ──
  static final SupabaseClient _aiClient = SupabaseClient(
    'https://ayvescksetiuekoyfqar.supabase.co',
    'sb_publishable_Bc_CXsA3BiuP36E4KxgkYQ_QmvyV7HT',
  );"""
content = content.replace(ai_client_code, "  // ── USING PRIMARY SUPABASE CLIENT FOR DECOUPLED AI SERVICES ──")

# 2. Update _workerHeaders
old_headers = """  static Map<String, String> _workerHeaders() {
    final headers = <String, String>{};
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        headers['x-primary-jwt'] = session.accessToken;
      }
    } catch (_) {}
    return headers;
  }"""
new_headers = """  static Map<String, String> _workerHeaders() {
    final headers = <String, String>{};
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        headers['x-primary-jwt'] = session.accessToken;
        headers['Authorization'] = 'Bearer ${session.accessToken}';
      }
    } catch (_) {}
    return headers;
  }"""
content = content.replace(old_headers, new_headers)

# 3. Add timeouts to req.send()
content = content.replace(
    "final streamed = await req.send();",
    "final streamed = await req.send().timeout(const Duration(seconds: 15));"
)

# 4. Add timeout to askNecxaWorker http.post
old_ask_necxa = """      final res = await http.post(
        Uri.parse('$_workerBase/api/assistant/chat/sync'),
        headers: {"Content-Type": "application/json", ..._workerHeaders()},
        body: jsonEncode({'message': userPrompt}),
      );"""
new_ask_necxa = """      final res = await http.post(
        Uri.parse('$_workerBase/api/assistant/chat/sync'),
        headers: {"Content-Type": "application/json", ..._workerHeaders()},
        body: jsonEncode({'message': userPrompt}),
      ).timeout(const Duration(seconds: 15));"""
content = content.replace(old_ask_necxa, new_ask_necxa)

# 5. Replace _aiClient with Supabase.instance.client
content = content.replace("_aiClient.functions.invoke", "Supabase.instance.client.functions.invoke")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("Done")
