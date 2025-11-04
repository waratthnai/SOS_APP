// lib/core/emergency_contact_db.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'emergency_contact_models.dart';

class EmergencyContactDB {
  static const String _key = 'emergency_contacts';

  /// บันทึกรายชื่อติดต่อฉุกเฉินทั้งหมด
  static Future<void> saveContacts(List<EmergencyContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = contacts.map((c) => c.toJson()).toList();
    await prefs.setString(_key, jsonEncode(jsonList));
  }

  /// โหลดรายชื่อติดต่อฉุกเฉินทั้งหมด
  static Future<List<EmergencyContact>> loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_key);
    
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    
    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((json) => EmergencyContact.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error loading emergency contacts: $e');
      return [];
    }
  }

  /// เพิ่มรายชื่อติดต่อใหม่
  static Future<void> addContact(EmergencyContact contact) async {
    final contacts = await loadContacts();
    contacts.add(contact);
    await saveContacts(contacts);
  }

  /// อัปเดตรายชื่อติดต่อ
  static Future<void> updateContact(EmergencyContact contact) async {
    final contacts = await loadContacts();
    final index = contacts.indexWhere((c) => c.id == contact.id);
    if (index != -1) {
      contacts[index] = contact;
      await saveContacts(contacts);
    }
  }

  /// ลบรายชื่อติดต่อ
  static Future<void> deleteContact(String contactId) async {
    final contacts = await loadContacts();
    contacts.removeWhere((c) => c.id == contactId);
    await saveContacts(contacts);
  }

  /// ล้างรายชื่อติดต่อทั้งหมด
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
