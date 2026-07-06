import 'package:http/http.dart' as http;

void main() async {
  try {
    print("Testing Worker API...");
    final res = await http.post(
      Uri.parse('https://api.necxa.uk/api/assistant/chat/sync'),
      headers: {"Content-Type": "application/json"},
      body: '{"message": "hello"}',
    );
    print("Worker Status: ${res.statusCode}");
    print("Worker Body: ${res.body}");
  } catch (e) {
    print("Worker Error: $e");
  }

  try {
    print("\nTesting Supabase Edge Function...");
    final res2 = await http.post(
      Uri.parse('https://ayvescksetiuekoyfqar.supabase.co/functions/v1/necxa-chat'),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer sb_publishable_Bc_CXsA3BiuP36E4KxgkYQ_QmvyV7HT",
      },
      body: '{"messages": [{"role": "user", "content": "hello"}]}',
    );
    print("Supabase Status: ${res2.statusCode}");
    print("Supabase Body: ${res2.body}");
  } catch (e) {
    print("Supabase Error: $e");
  }
}
