#!/bin/bash

# Parse parameters
WK_DIR=$1
OUT_NAME_before_parsing=$2    # For parallel using, OUT_NAME here is a absolute path, so the OUT_NAME in code cannot be added to a correct absolute path
VALID_PAIRS=$3
SAMPLE=$4
PEAKFILE=$5
MIN_DIST=$6
MAX_DIST=$7
MERGE_GAP=$8
HALF_LEN=$9
UCSC=${10}
NO_MERGE=${11}


# parsing the $OUT_NAME_before_parsing
OUT_NAME=${OUT_NAME_before_parsing##*/}

echo "new OUT_NAME is: ${OUT_NAME}"


# Log from the shell script side
LOG_FILE="${WK_DIR}/${OUT_NAME}/${OUT_NAME}.hichipper.log"
# 20250903 changed by Tao
# LOG_FILE="${OUT_NAME}/out.hichipper.log"

echo "`date`: Processing ${SAMPLE}" | tee -a $LOG_FILE

# Merge gaps; check bedtools
echo "`date`: Intersecting PETs with anchors" | tee -a $LOG_FILE
if [ "$NO_MERGE" = true ] ; then
	bedtools sort -i "${PEAKFILE}" | awk '{print $1"\t"$2"\t"$3}' > "${WK_DIR}/${OUT_NAME}/${SAMPLE}_temporary_peaks.merged.bed.tmp"
	echo "`date`: nearby anchors will not be merged; WARNING: this may inflate summary statistics." | tee -a $LOG_FILE
else
	bedtools sort -i "${PEAKFILE}" | bedtools merge -d $MERGE_GAP -i stdin > "${WK_DIR}/${OUT_NAME}/${SAMPLE}_temporary_peaks.merged.bed.tmp"
	echo "`date`: Finished the anchor merging." | tee -a $LOG_FILE
fi

minimumsize=10
actualsize=$(wc -c < "${WK_DIR}/${OUT_NAME}/${SAMPLE}_temporary_peaks.merged.bed.tmp")
if [ $actualsize -ge $minimumsize ]; then
    echo "`date`: Finished the anchor processing." | tee -a $LOG_FILE
else
    echo "`date`: Something went wrong in determining peaks for anchor inference; rerun with the `--keep-temp-files` flag to debug." | tee -a $LOG_FILE
    exit
fi

# Count reads in anchors; spit out only valid pairs sorted and pretty
Total_PETs=`wc -l $VALID_PAIRS`
cat $VALID_PAIRS | awk -v RL="$HALF_LEN" '{print $2 "\t" $3 - RL "\t" $3 + RL}' | awk '$2 > 0 {print $0}' | coverageBed -a stdin -b "${WK_DIR}/${OUT_NAME}/${SAMPLE}_temporary_peaks.merged.bed.tmp" -counts | awk '{sum += $4} END {print sum}' > "${WK_DIR}/${OUT_NAME}/${SAMPLE}.peakReads.tmp"
cat $VALID_PAIRS | awk -v RL="$HALF_LEN" '{print $5 "\t" $6 - RL "\t" $6 + RL}' | awk '$2 > 0 {print $0}' | coverageBed -a stdin -b "${WK_DIR}/${OUT_NAME}/${SAMPLE}_temporary_peaks.merged.bed.tmp" -counts | awk '{sum += $4} END {print sum}' >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.peakReads.tmp"
cat $VALID_PAIRS | awk -v RL="$HALF_LEN" '{if ($2<$5 || ($2==$5 && $3<=$6)) print $2,$3-RL,$3+RL,$5,$6-RL,$6+RL; else print $5,$6-RL,$6+RL,$2,$3-RL,$3+RL}' 'OFS=\t' | awk '$2 > 0 && $5 > 0 {print $0}' | sort -k1,1n -k2,2n -k4,4n -k5,5n > "${WK_DIR}/${OUT_NAME}/${SAMPLE}_interactions.bedpe.tmp"
READS_IN_ANCHORS=`awk '{sum += $1} END {print sum}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}.peakReads.tmp" | awk '{print $1}'`

# Valid interaction statistics
intrachromosomal_valid_small=`awk -v MIN_DIST="$MIN_DIST" '$1 == $4 && (($5+$6)/2 - ($2+$3)/2)<=MIN_DIST {print $0}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}_interactions.bedpe.tmp" | wc -l | awk '{print $1}'`
echo "`date`: Intrachromosomal_valid_small=${intrachromosomal_valid_small}" | tee -a $LOG_FILE
intrachromosomal_valid_med=`awk -v MIN_DIST="$MIN_DIST" -v MAX_DIST="$MAX_DIST" '$1 == $4 && (($5+$6)/2 - ($2+$3)/2)>=MIN_DIST && (($5+$6)/2 - ($2+$3)/2)<=MAX_DIST {print $0}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}_interactions.bedpe.tmp" | wc -l | awk '{print $1}'`
echo "`date`: Intrachromosomal_valid_med=${intrachromosomal_valid_med}" | tee -a $LOG_FILE
intrachromosomal_valid_large=`awk -v MAX_DIST="$MAX_DIST" '$1 == $4 && (($5+$6)/2 - ($2+$3)/2)>=MAX_DIST {print $0}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}_interactions.bedpe.tmp" | wc -l | awk '{print $1}'`
echo "`date`: Intrachromosomal_valid_large=${intrachromosomal_valid_large}" | tee -a $LOG_FILE
intrachoromosomal_valid_all=$(($intrachromosomal_valid_small+$intrachromosomal_valid_med+$intrachromosomal_valid_large))

NUM_PEAKS=`wc -l "${WK_DIR}/${OUT_NAME}/${SAMPLE}_temporary_peaks.merged.bed.tmp" | awk '{print $1}'`
echo "`date`: Total number of anchors used: ${NUM_PEAKS}" | tee -a $LOG_FILE
echo "`date`: Total number of reads in anchors: ${READS_IN_ANCHORS}" | tee -a $LOG_FILE

# Overlap reads with anchors
cat "${WK_DIR}/${OUT_NAME}/${SAMPLE}_interactions.bedpe.tmp" | awk '{print $1"\t"$2"\t"$3}' | bedtools intersect -loj -a stdin -b "${WK_DIR}/${OUT_NAME}/${SAMPLE}_temporary_peaks.merged.bed.tmp" | awk '{print $4,$5,$6}' OFS='\t' > "${WK_DIR}/${OUT_NAME}/${SAMPLE}_anchor1.bed.tmp"
cat "${WK_DIR}/${OUT_NAME}/${SAMPLE}_interactions.bedpe.tmp" | awk '{print $4"\t"$5"\t"$6}' | bedtools intersect -loj -a stdin -b "${WK_DIR}/${OUT_NAME}/${SAMPLE}_temporary_peaks.merged.bed.tmp" | awk '{print $4,$5,$6}' OFS='\t' > "${WK_DIR}/${OUT_NAME}/${SAMPLE}_anchor2.bed.tmp"

paste "${WK_DIR}/${OUT_NAME}/${SAMPLE}_anchor1.bed.tmp" "${WK_DIR}/${OUT_NAME}/${SAMPLE}_anchor2.bed.tmp" | awk '{if ($1 != "." && $4 != ".") print}' > "${WK_DIR}/${OUT_NAME}/${SAMPLE}_anchor.interactions.bedpe.tmp"

cut -f1-6  "${WK_DIR}/${OUT_NAME}/${SAMPLE}_anchor.interactions.bedpe.tmp" | sort | uniq -c | awk '{print $2,$3,$4,$5,$6,$7,".",$1}' >  "${WK_DIR}/${OUT_NAME}/${SAMPLE}.loop_counts.bedpe.tmp"


Mapped_unique_intra_quality_anchor=`awk '$1 == $4 {print $0}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}_anchor.interactions.bedpe.tmp" | wc -l | awk '{print $1}'`
Mapped_unique_intra_quality_anchor_small=`awk -v MIN_DIST="$MIN_DIST" '$1 == $4 && (($5+$6)/2 - ($2+$3)/2)<=MIN_DIST {print $0}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}_anchor.interactions.bedpe.tmp" | wc -l | awk '{print $1}'`
Mapped_unique_intra_quality_anchor_med=`awk -v MIN_DIST="$MIN_DIST" -v MAX_DIST="$MAX_DIST" '$1 == $4 && (($5+$6)/2 - ($2+$3)/2)>=MIN_DIST && (($5+$6)/2 - ($2+$3)/2)<=MAX_DIST {print $0}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}_anchor.interactions.bedpe.tmp" | wc -l | awk '{print $1}'`
Mapped_unique_intra_quality_anchor_large=`awk -v MAX_DIST="$MAX_DIST" '$1 == $4 && (($5+$6)/2 - ($2+$3)/2)>=MAX_DIST {print $0}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}_anchor.interactions.bedpe.tmp" | wc -l | awk '{print $1}'`
echo "`date`: Mapped_unique_intra_quality_anchor=${Mapped_unique_intra_quality_anchor}" | tee -a $LOG_FILE
echo "`date`: Mapped_unique_intra_quality_anchor_small=${Mapped_unique_intra_quality_anchor_small}" | tee -a $LOG_FILE
echo "`date`: Mapped_unique_intra_quality_anchor_med=${Mapped_unique_intra_quality_anchor_med}" | tee -a $LOG_FILE
echo "`date`: Mapped_unique_intra_quality_anchor_large=${Mapped_unique_intra_quality_anchor_large}" | tee -a $LOG_FILE

# Produce final output
awk '$1 != $4 {print $0}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}.loop_counts.bedpe.tmp" > "${WK_DIR}/${OUT_NAME}/${SAMPLE}.inter.loop_counts.bedpe"
awk '$1 == $4 {print $0}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}.loop_counts.bedpe.tmp" > "${WK_DIR}/${OUT_NAME}/${SAMPLE}.intra.loop_counts.bedpe"
awk -v MIN_DIST="$MIN_DIST" -v MAX_DIST="$MAX_DIST" '$1 == $4 && $2 != $5 && (($5+$6)/2 - ($2+$3)/2)>=MIN_DIST && (($5+$6)/2 - ($2+$3)/2)<=MAX_DIST {print $0}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}.loop_counts.bedpe.tmp" >  "${WK_DIR}/${OUT_NAME}/${SAMPLE}.filt.intra.loop_counts.bedpe"

# Produce UCSC Output if requested
if [ "$UCSC" = true ] ; then
    echo "`date`: Creating UCSC Compatible files; make sure tabix and bgzip are available in the environment or this will not work." | tee -a $LOG_FILE
    awk '{print $1"\t"$2"\t"$3"\t"$4":"$5"-"$6","$8"\t"(NR*2-1)"\t.\n"$4"\t"$5"\t"$6"\t"$1":"$2"-"$3","$8"\t"(NR*2)"\t."}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}.filt.intra.loop_counts.bedpe" | bedtools sort  > "${WK_DIR}/${OUT_NAME}/${SAMPLE}.interaction.txt"
    bgzip "${WK_DIR}/${OUT_NAME}/${SAMPLE}.interaction.txt"
    tabix -p bed "${WK_DIR}/${OUT_NAME}/${SAMPLE}.interaction.txt.gz"
fi

# Move final peaks 
cp "${WK_DIR}/${OUT_NAME}/${SAMPLE}_temporary_peaks.merged.bed.tmp" "${WK_DIR}/${OUT_NAME}/${SAMPLE}.anchors.bed"

# Finalize 
Loop_PETs=`awk '{sum += $8} END {print sum}' "${WK_DIR}/${OUT_NAME}/${SAMPLE}.filt.intra.loop_counts.bedpe"`
echo "`date`: Loop_PETs=${Loop_PETs}" | tee -a $LOG_FILE

# Write out summary statistics
echo "Total_PETs=${Total_PETs}" > "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"

echo "Mapped_unique_quality_pairs=${Total_PETs}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "Mapped_unique_quality_valid_pairs=${Total_PETs}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "Mapped_unique_quality_valid_intrachromosomal=${Total_PETs}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "Intrachromosomal_valid_small=${intrachromosomal_valid_small}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "Intrachromosomal_valid_med=${intrachromosomal_valid_med}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "Intrachromosomal_valid_large=${intrachromosomal_valid_large}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "Mapped_unique_intra_quality_anchor=${Mapped_unique_intra_quality_anchor}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "Mapped_unique_intra_quality_anchor_small=${Mapped_unique_intra_quality_anchor_small}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "Mapped_unique_intra_quality_anchor_med=${Mapped_unique_intra_quality_anchor_med}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "Mapped_unique_intra_quality_anchor_large=${Mapped_unique_intra_quality_anchor_large}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "Number_of_Anchors=${NUM_PEAKS}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "MIN_LENGTH=${MIN_DIST}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "MAX_LENGTH=${MAX_DIST}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
echo "READS_IN_ANCHORS=${READS_IN_ANCHORS}" >> "${WK_DIR}/${OUT_NAME}/${SAMPLE}.stat"
