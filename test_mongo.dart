import 'package:mongo_dart/mongo_dart.dart';

void main() async {
  print('Connecting to MongoDB...');
  final db = await Db.create("mongodb+srv://Muwanguzi:K7kkpea8VOKJhabr@necxalive.b417dk3.mongodb.net/necxalive?appName=necxalive");
  try {
    await db.open();
    print('MongoDB Connected Successfully!');
    await db.close();
  } catch (e) {
    print('Failed to connect: $e');
  }
}
