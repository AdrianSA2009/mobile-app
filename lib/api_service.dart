import 'dart:convert';
import 'package:http/http.dart' as http;

class FinanceApiService {
  // TODO: Masukkan Client ID dan Client Secret dari Dashboard (Sandbox) Anda
  final String clientId = 'f8af9d74-ec7c-4446-8048-84af1efaaf4d';
  final String clientSecret = 'K481xuBhUyVGNo0T7iUnuaBYxwiV1v';
  
  // URL Sandbox (Contoh ini menggunakan format Brick, sesuaikan jika dokumentasinya berbeda)
  final String baseUrl = 'https://sandbox.onebrick.io/v1'; 

  /// Fungsi untuk mendapatkan Public Access Token
  Future<String?> getPublicToken() async {
    final url = Uri.parse('$baseUrl/auth/token');
    
    // API keuangan biasanya meminta ClientID:ClientSecret di-encode menjadi Base64
    final String credentials = base64Encode(utf8.encode('$clientId:$clientSecret'));

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Basic $credentials',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        
        // Mengambil token dari JSON yang dikembalikan
        final String token = responseData['data']['access_token'];
        print('✅ Berhasil mendapatkan Token: $token');
        return token;
      } else {
        print('❌ Gagal Auth. Status Code: ${response.statusCode}');
        print('Pesan Error: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Terjadi kesalahan jaringan: $e');
      return null;
    }
  }
}