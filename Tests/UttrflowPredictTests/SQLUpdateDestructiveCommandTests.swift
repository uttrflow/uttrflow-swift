import Testing

@testable import UttrflowPredict

@Suite("Recognising SQL updates that change every row")
struct SQLUpdateDestructiveCommandTests {
    @Test(
        "An UPDATE without its own WHERE is destructive across SQL clients.",
        arguments: [
            "mysql -e \"UPDATE orders SET status='x'\"",
            "psql -c \"UPDATE users SET admin=true\"",
            "sqlite3 app.db \"UPDATE t SET a=0\"",
            "duckdb -c \"UPDATE orders SET status='x'\"",
            "clickhouse-client -q \"UPDATE orders SET status='x'\"",
            "UPDATE orders SET status='x'",
        ])
    func updateWithoutWhereIsDestructive(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line)")
    }

    @Test(
        "Only a WHERE in the same UPDATE statement makes the update ordinary.",
        arguments: [
            "mysql -e \"UPDATE orders SET status='x' WHERE id=1\"",
            "psql -c \"UPDATE users SET admin=true WHERE id=1\"",
            "sqlite3 app.db \"UPDATE t SET a=0 WHERE id=1\"",
            "duckdb -c \"UPDATE orders SET status='x' WHERE id=1\"",
            "clickhouse-client -q \"UPDATE orders SET status='x' WHERE id=1\"",
            "UPDATE orders SET status='x' WHERE id=1",
        ])
    func updateWithWhereIsOrdinary(_ line: String) {
        #expect(!DestructiveCommand.matches(line), "\(line)")
    }

    @Test(
        "Comments, quoted strings and later statements cannot supply an UPDATE WHERE.",
        arguments: [
            "psql -c \"UPDATE t SET x=1 -- WHERE id=1\"",
            "mysql -e \"UPDATE t SET x=1 /* WHERE id=1 */\"",
            "mysql -e \"UPDATE t SET x=1 # WHERE id=1\n\"",
            "psql -c \"UPDATE t SET note=$$WHERE id=1$$\"",
            "psql -c \"UPDATE t SET note=$body$WHERE id=1$body$\"",
            "psql -c \"UPDATE t SET note=$Tag$$tag$ WHERE id=1 $Tag$\"",
            "sqlite3 db \"UPDATE t SET note='WHERE';\"",
            "psql -c \"UPDATE t SET x=1; SELECT * FROM t WHERE id=1\"",
            "psql -c \"UPDATE t SET x=(SELECT x FROM s WHERE id=1)\"",
        ])
    func commentsAndOtherStatementsDoNotProtectUpdate(_ line: String) {
        #expect(DestructiveCommand.matches(line), "\(line)")
    }

    @Test("A later unguarded UPDATE is destructive even after a guarded statement.")
    func laterUnguardedUpdateIsDestructive() {
        #expect(DestructiveCommand.matches("psql -c \"UPDATE t SET x=1 WHERE id=1; UPDATE t SET x=2\""))
    }

    @Test("A guarded sibling data-modifying CTE cannot guard an unguarded UPDATE.")
    func siblingDataModifyingCTEsKeepTheirOwnWhereClauses() {
        #expect(
            DestructiveCommand.matches(
                "psql -c \"WITH a AS (UPDATE t1 SET x=1 RETURNING *), b AS (UPDATE t2 SET x=1 WHERE id=1 RETURNING *) SELECT * FROM a CROSS JOIN b\""
            ))
    }

    @Test("A comment may separate the UPDATE from its table and guarded clause.")
    func commentsBetweenUpdateTokensAreIgnored() {
        #expect(!DestructiveCommand.matches("mysql -e \"UPDATE /* all rows? */ t SET x=1 WHERE id=1\""))
    }

    @Test("SQL Server temporary table names do not start MySQL comments.")
    func sqlServerTemporaryTableUpdateWithWhereIsOrdinary() {
        #expect(!DestructiveCommand.matches("sqlcmd -Q \"UPDATE #temp SET x=1 WHERE id=1\""))
    }

    @Test("SQL that only mentions UPDATE in a string remains ordinary.")
    func updateInsideStringIsNotAStatement() {
        #expect(!DestructiveCommand.matches("psql -c \"SELECT 'UPDATE t SET x=1'\""))
    }
}
