import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDb {
  static final LocalDb instance = LocalDb._();
  static Database? _db;

  LocalDb._();

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'kokonuts_pos.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE catalog_items (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            group_id TEXT NOT NULL,
            modifier_group_ids TEXT NOT NULL DEFAULT '[]',
            bundle_modifier_groups TEXT NOT NULL DEFAULT '[]',
            updated_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE catalog_groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            updated_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE catalog_modifier_groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            selection_type TEXT NOT NULL,
            min_selections INTEGER NOT NULL DEFAULT 0,
            max_selections INTEGER NOT NULL DEFAULT 1,
            updated_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE catalog_modifiers (
            id TEXT PRIMARY KEY,
            modifier_group_id TEXT NOT NULL,
            name TEXT NOT NULL,
            price_adjustment REAL NOT NULL DEFAULT 0,
            sort_order INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE catalog_payment_modes (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_ms INTEGER NOT NULL,
            shift_id INTEGER NOT NULL,
            employee_id INTEGER NOT NULL,
            customer_id INTEGER,
            payment_method TEXT NOT NULL,
            subtotal REAL NOT NULL,
            bill_discount REAL NOT NULL DEFAULT 0,
            cashback_redeemed REAL NOT NULL DEFAULT 0,
            total REAL NOT NULL,
            cash_received REAL NOT NULL DEFAULT 0,
            change_amount REAL NOT NULL DEFAULT 0,
            queue_number INTEGER NOT NULL,
            items_json TEXT NOT NULL,
            cashback_customer_id INTEGER,
            cashback_amount REAL NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'pending',
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            synced_ms INTEGER,
            receipt_number TEXT,
            receipt_id INTEGER
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS catalog_payment_modes (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE catalog_items ADD COLUMN bundle_modifier_groups TEXT NOT NULL DEFAULT '[]'",
          );
        }
      },
    );
  }
}
