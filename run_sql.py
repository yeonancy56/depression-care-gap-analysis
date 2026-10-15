# Runs one or more .sql files against tmmc.duckdb, in order.
# Usage: python3 run_sql.py queries/00_load.sql queries/01_deidentify.sql
import sys
import duckdb

con = duckdb.connect("tmmc.duckdb")
# Synthea stores times in UTC. Turning a time into a calendar date depends on the time zone,
# so fix it to Torrance's zone: results are then the same on any computer.
con.execute("SET TimeZone = 'America/Los_Angeles'")
for path in sys.argv[1:]:
    con.execute(open(path).read())
    print("ran", path)
