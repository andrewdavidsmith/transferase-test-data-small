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

if [ ! -d "${DATADIR}/xsym_mm39" ] || \
       [ ! -d "${DATADIR}/xsym_hg38" ] || \
       [ ! -d "${DATADIR}/intervals" ] || \
       [ ! -d "${DATADIR}/methylomes" ] || \
       [ ! -d "${DATADIR}/indexes" ]; then
    echo "Error: could not find required directory"
    exit 1
fi

if [ ! -f "${DATADIR}/methylomes_hg38.txt" ] || \
       [ ! -f "${DATADIR}/methylomes_mm39.txt" ] || \
       [ ! -f "${DATADIR}/hg38.fa.gz" ] || \
       [ ! -f "${DATADIR}/mm39.fa.gz" ] || \
       [ ! -f "${DATADIR}/intervals_hg38.txt" ] || \
       [ ! -f "${DATADIR}/intervals_mm39.txt" ]; then
    echo "Error: could not find a required file"
    exit 1
fi

make_index() {
    species=$1
    xfr index \
        --genome "${DATADIR}/${species}.fa.gz" \
        --index-dir "${DATADIR}/indexes" \
        --log-level critical
}

format_methylomes() {
    species=$1
    while read -r methylome; do
        xfr format -g "${species}" \
            -x indexes -d methylomes \
            -m "${DATADIR}/xsym_${species}/${methylome}.xsym.gz" \
            --log-level critical
    done < "${DATADIR}/methylomes_${species}.txt"
}

run_queries() {
    species=$1
    while read -r intervals; do
        outfile=$(basename "${intervals}" '.bed').txt
        xfr query --local -g "${species}" \
            -x "${DATADIR}/indexes" \
            -d "${DATADIR}/methylomes" \
            -M "methylomes_${species}.txt" \
            -o "output/${outfile}" \
            -i "intervals/${intervals}" \
            --out-fmt dfscores \
            --log-level critical
    done < "${DATADIR}/intervals_${species}.txt"
}

for species in hg38 mm39; do
    time {
        make_index $species;
        TIMEFORMAT="make_index $species %3R";
    }
done

for species in hg38 mm39; do
    time {
        format_methylomes $species;
        TIMEFORMAT="format_methylomes $species %3R";
    }
done

for species in hg38 mm39; do
    time {
        run_queries $species;
        TIMEFORMAT="run_queries $species %3R";
    }
done

xfr check -x "${DATADIR}/indexes" -d "${DATADIR}/methylomes" \
    --log-level critical
