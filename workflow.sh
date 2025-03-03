#!/bin/bash
# MIT License
#
# Copyright (c) 2025 Andrew Smith
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# ADS: taking care that everything should be expanded locally
# shellcheck disable=SC2029

set -o errexit -o pipefail -o noclobber -o nounset

DATADIR=$1

make_index() {
    species=$1
    xfr index \
        --genome "${DATADIR}/${species}.fa.gz" \
        --index-dir "${DATADIR}/indexes" \
        --log-level error
}

format_methylomes() {
    species=$1
    while read -r methylome_name; do
        xfr format -g "${species}" \
            -x "${DATADIR}/indexes" -d "${DATADIR}/methylomes" \
            -m "${DATADIR}/xsym_${species}/${methylome_name}.xsym.gz" \
            --log-level error
    done < "${DATADIR}/methylomes_${species}.txt"
}

run_local_queries() {
    species=$1
    while read -r intervals_file; do
        outfile=$(basename "${intervals_file}" '.bed')_local.txt
        xfr query --local -g "${species}" \
            -x "${DATADIR}/indexes" \
            -d "${DATADIR}/methylomes" \
            -m "${DATADIR}/methylomes_${species}.txt" \
            -o "${DATADIR}/output/${outfile}" \
            -i "${DATADIR}/intervals/${intervals_file}" \
            -r 1 \
            --out-fmt dfscores \
            --log-level error
    done < "${DATADIR}/intervals_${species}.txt"
}

run_remote_queries() {
    species=$1
    while read -r intervals_file; do
        outfile=$(basename "${intervals_file}" '.bed')_remote.txt
        while read -r methylome_name; do
            xfr query -g "${species}" \
                -m "${methylome_name}" \
                -o "${DATADIR}/output/${outfile}" \
                -i "${DATADIR}/intervals/${intervals_file}" \
                --log-level error
        done < "${DATADIR}/methylomes_${species}.txt"
    done < "${DATADIR}/intervals_${species}.txt"
}

# Check that required directories from the repo exist
if [ ! -d "${DATADIR}/xsym_mm39" ] || \
       [ ! -d "${DATADIR}/xsym_hg38" ] || \
       [ ! -d "${DATADIR}/intervals" ]; then
    echo "Error: could not find required directory"
    exit 1
fi

# Check that required files from the repo exist
if [ ! -f "${DATADIR}/methylomes_hg38.txt" ] || \
       [ ! -f "${DATADIR}/methylomes_mm39.txt" ] || \
       [ ! -f "${DATADIR}/hg38.fa.gz" ] || \
       [ ! -f "${DATADIR}/mm39.fa.gz" ] || \
       [ ! -f "${DATADIR}/intervals_hg38.txt" ] || \
       [ ! -f "${DATADIR}/intervals_mm39.txt" ]; then
    echo "Error: could not find a required file"
    exit 1
fi

# Make the directory for genome indexes
if [ ! -d "${DATADIR}/indexes" ]; then
    mkdir "${DATADIR}/indexes"
fi

# Generate the genome indexes
for species in hg38 mm39; do
    time {
        make_index "${species}";
        TIMEFORMAT="make_index ${species} %3R";
    }
done

# Make the directory for methylomes
if [ ! -d "${DATADIR}/methylomes" ]; then
    mkdir "${DATADIR}/methylomes"
fi

# Generate the methylomes
for species in hg38 mm39; do
    time {
        format_methylomes "${species}";
        TIMEFORMAT="format_methylomes ${species} %3R";
    }
done

# Make the output directory for queries
if [ ! -d "${DATADIR}/output" ]; then
    mkdir "${DATADIR}/output"
fi

# Run all the queries
for species in hg38 mm39; do
    time {
        run_local_queries "${species}";
        TIMEFORMAT="run_local_queries ${species} %3R";
    }
done

# Run the concistency check
xfr check -x "${DATADIR}/indexes" -d "${DATADIR}/methylomes" \
    --log-level error

# Now try a config and a remote query
time {
    xfr config --genomes hg38,mm39 --quiet
    TIMEFORMAT="config: %3R";
}

for species in hg38 mm39; do
    time {
        run_remote_queries "${species}";
        TIMEFORMAT="run_remote_query: %3R";
    }
done

# Check all the hashes; this currently has an issue with relative
# paths
sha256sum --quiet -c "${DATADIR}/sha256sum.txt"
