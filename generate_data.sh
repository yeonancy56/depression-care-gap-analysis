#!/bin/bash
# Generates the project's simulated data: 10 Synthea runs of 1,000 Torrance residents.
# -s = seed (42-51), so the same patients come out every time.
# -r / -e = fixed reference and end date, so the result doesn't depend on the day you run it.
# Each run goes to its own folder: output/seed_<n>/csv/
JAVA=${JAVA:-/opt/homebrew/opt/openjdk/bin/java}
for s in 42 43 44 45 46 47 48 49 50 51; do
    "$JAVA" -Xmx4g -jar synthea-with-dependencies.jar -p 1000 -s $s -r 20261001 -e 20261001 \
        --exporter.baseDirectory=./output/seed_$s/ \
        --exporter.csv.export=true \
        --exporter.fhir.export=false \
        --exporter.hospital.fhir.export=false \
        --exporter.practitioner.fhir.export=false \
        --exporter.years_of_history=5 \
        California Torrance > synthea_seed_$s.log 2>&1
    echo "seed $s exit $? $(grep -o 'Records: total=[0-9]*, alive=[0-9]*, dead=[0-9]*' synthea_seed_$s.log)"
done
