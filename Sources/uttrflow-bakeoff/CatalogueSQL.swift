import UttrflowPredict

extension FixtureCatalogue {
    /// Queries over two invented schemas in a SQL editor, whole statements and the clauses of one in progress.
    static let sql: [Scenario] = [
        Scenario(
            category: "sql", name: "shop",
            situation: editor(
                database: "shop_prod",
                script: """
                    -- shop: users(id, email, created_at), orders(id, user_id, total, status, created_at), \
                    products(id, name, price, stock)
                    SELECT * FROM users LIMIT 10;
                    SELECT count(*) FROM orders;
                    """,
                recent: [
                    "SELECT count(*) FROM orders;", "SELECT * FROM users LIMIT 10;",
                    "SELECT * FROM products WHERE stock = 0;",
                ]),
            cuts: .query, determinacy: .query, band: 1...80, forbidden: ["LIMIT 10;"],
            known: [
                "SELECT * FROM products;", "SELECT id FROM users;", "UPDATE users SET",
                "ALTER TABLE products ALTER COLUMN price TYPE numeric;",
            ],
            lines: [
                "SELECT * FROM users WHERE id = 42;", "SELECT count(*) FROM orders WHERE status = 'paid';",
                "SELECT id, total FROM orders ORDER BY created_at DESC LIMIT 20;",
                "SELECT name, price FROM products WHERE stock < 10;",
                "INSERT INTO products (name, price, stock) VALUES ('Kettle', 39.00, 12);",
                "UPDATE orders SET status = 'shipped' WHERE id = 1042;",
                "UPDATE products SET stock = stock - 1 WHERE id = 7;",
                "DELETE FROM orders WHERE status = 'cancelled' AND created_at < '2025-01-01';",
                "SELECT u.email, o.total FROM users u JOIN orders o ON o.user_id = u.id;",
                "SELECT status, count(*) FROM orders GROUP BY status;",
                "ALTER TABLE products ADD COLUMN sku text;",
                Line("CREATE TABLE refunds (id serial PRIMARY KEY, order_id int);", determinacy: .any),
            ]),
        Scenario(
            category: "sql", name: "library",
            situation: editor(
                database: "library",
                script: """
                    -- library: books(id, title, author_id, year), members(id, name, joined_at), \
                    loans(id, book_id, member_id, due_at, returned_at)
                    SELECT * FROM books LIMIT 5;
                    """,
                recent: ["SELECT * FROM books LIMIT 5;", "SELECT count(*) FROM loans;"]),
            cuts: .query, determinacy: .query, band: 1...80, forbidden: ["LIMIT 5;"],
            known: ["SELECT * FROM members;", "SELECT * FROM loans;", "UPDATE members SET"],
            lines: [
                "SELECT title, year FROM books WHERE author_id = 3;",
                "SELECT * FROM members WHERE joined_at > '2026-01-01';",
                "SELECT count(*) FROM loans WHERE returned_at IS NULL;",
                "UPDATE loans SET returned_at = now() WHERE id = 88;",
                "INSERT INTO members (name, joined_at) VALUES ('Sam', now());",
                "DELETE FROM loans WHERE returned_at < '2020-01-01';",
                "SELECT b.title, m.name FROM loans l JOIN books b ON b.id = l.book_id;",
                "SELECT author_id, count(*) FROM books GROUP BY author_id ORDER BY 2 DESC;",
            ]),
        Scenario(
            category: "sql", name: "shop-clauses",
            situation: editor(
                database: "shop_prod",
                script: """
                    -- shop: users(id, email, created_at), orders(id, user_id, total, status, created_at)
                    SELECT u.email, count(o.id) AS order_count
                    FROM users u
                    JOIN orders o ON o.user_id = u.id
                    """,
                recent: [
                    "JOIN orders o ON o.user_id = u.id", "FROM users u",
                    "SELECT u.email, count(o.id) AS order_count",
                ]),
            cuts: .clause, determinacy: .query, band: 1...60, forbidden: ["FROM users u", "count(o.id) AS"],
            known: ["WHERE u.created_at > '2026-01-01'", "ORDER BY u.email", "GROUP BY 1"],
            lines: [
                "WHERE o.status = 'paid'", "GROUP BY u.email", "ORDER BY order_count DESC",
                "HAVING count(o.id) > 3",
                Line("LIMIT 50;", determinacy: .any), "LEFT JOIN products p ON p.id = o.product_id",
            ]),
        Scenario(
            category: "sql", name: "library-clauses",
            situation: editor(
                database: "library",
                script: """
                    -- library: books(id, title, author_id, year), loans(id, book_id, member_id, due_at, returned_at)
                    SELECT b.title, l.due_at
                    FROM loans l
                    JOIN books b ON b.id = l.book_id
                    """,
                recent: ["JOIN books b ON b.id = l.book_id", "FROM loans l", "SELECT b.title, l.due_at"]),
            cuts: .clause, determinacy: .query, band: 1...60,
            forbidden: ["FROM loans l", "b.id = l.book_id"],
            known: ["WHERE l.due_at < now()", "ORDER BY b.title"],
            lines: [
                "WHERE l.returned_at IS NULL", "ORDER BY l.due_at", "AND l.member_id = 12",
                Line("LIMIT 100;", determinacy: .any),
            ]),
    ]

    /// A SQL editor whose script holds the schema comment and the statements run so far.
    static func editor(database: String, script: String, recent: [String]) -> GenerationSituation {
        GenerationSituation(
            application: "DBeaver", field: "SQL editor", document: database, preceding: script,
            windowTitle: "\(database) — Script", recentLines: recent, isMultiline: true)
    }
}
