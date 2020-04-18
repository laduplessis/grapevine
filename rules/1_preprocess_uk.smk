import datetime

date = datetime.date.today()

rule uk_unify_headers:
    input:
        fasta = config["latest_uk_fasta"],
        metadata = config["latest_uk_metadata"]
    output:
        fasta = temp(config["output_path"] + "/1/uk_latest.unify_headers.fasta"),
        metadata = temp(config["output_path"] + "/1/uk_latest.unify_headers.csv")
    log:
        config["output_path"] + "/logs/1_uk_unify_headers.log"
    shell:
        """
        datafunk set_uniform_header \
          --input_fasta {input.fasta} \
          --input_metadata {input.metadata} \
          --output_fasta {output.fasta} \
          --output_metadata {output.metadata} \
          --log {log} \
          --cog_uk
        """

rule uk_add_epi_week:
    input:
        metadata = rules.uk_unify_headers.output.metadata
    output:
        metadata = config["output_path"] + "/1/uk_latest.unify_headers.epi_week.csv"
    log:
        config["output_path"] + "/logs/1_uk_add_epi_week.log"
    shell:
        """
        datafunk add_epi_week \
        --input_metadata {input.metadata} \
        --output_metadata {output.metadata} \
        --date_column collection_date \
        --epi_column_name edin_epi_week &> {log}
        """

rule uk_annotate_to_remove_duplicates:
    input:
        fasta = rules.uk_unify_headers.output.fasta,
        metadata = rules.uk_add_epi_week.output.metadata
    output:
        metadata = config["output_path"] + "/1/uk_latest.unify_headers.epi_week.annotated.csv"
    log:
        config["output_path"] + "/logs/1_uk_annotate_to_remove_duplicates.log"
    shell:
        """
        fastafunk annotate \
          --in-fasta {input.fasta} \
          --in-metadata {input.metadata} \
          --out-metadata {output.metadata} \
          --log-file {log} \
          --add-cov-id
        """

rule uk_remove_duplicates:
    input:
        fasta = rules.uk_unify_headers.output.fasta,
        metadata = rules.uk_annotate_to_remove_duplicates.output.metadata
    output:
        fasta = config["output_path"] + "/1/uk_latest.unify_headers.epi_week.deduplicated.fasta",
        metadata = config["output_path"] + "/1/uk_latest.unify_headers.epi_week.deduplicated.csv"
    log:
        config["output_path"] + "/logs/1_uk_remove_duplicates.log"
    shell:
        """
        fastafunk subsample \
          --in-fasta {input.fasta} \
          --in-metadata {input.metadata} \
          --group-column cov_id \
          --index-column sequence_name \
          --out-fasta {output.fasta} \
          --out-metadata {output.metadata} \
          --sample-size 1 \
          --select-by-min-column gaps &> {log}
        """

rule uk_filter_short_sequences:
    input:
        fasta = rules.uk_remove_duplicates.output.fasta
    params:
        min_covg = config["min_covg"],
        min_length = config["min_length"]
    output:
        fasta = config["output_path"] + "/1/uk_latest.unify_headers.epi_week.deduplicated.length_fitered.fasta"
    log:
        config["output_path"] + "/logs/1_uk_filter_short_sequences.log"
    shell:
        """
        datafunk filter_fasta_by_covg_and_length \
          -i {input.fasta} \
          -o {output.fasta} \
          --min_length {params.min_length} &> {log}
        """

rule uk_minimap2_to_reference:
    input:
        fasta = rules.uk_filter_short_sequences.output,
        reference = config["reference_fasta"]
    output:
        sam = config["output_path"] + "/1/uk_latest.unify_headers.epi_week.deduplicated.length_fitered.mapped.sam"
    log:
        config["output_path"] + "/logs/1_uk_minimap2_to_reference.log"
    shell:
        """
        minimap2 -a -x asm5 {input.reference} {input.fasta} > {output.sam} 2> {log}
        """

rule uk_remove_insertions_and_trim:
    input:
        sam = rules.uk_minimap2_to_reference.output.sam,
        reference = config["reference_fasta"]
    params:
        trim_start = config["trim_start"],
        trim_end = config["trim_end"],
        insertions = config["output_path"] + "/1/uk_insertions.txt"
    output:
        fasta = config["output_path"] + "/1/uk_latest.unify_headers.epi_week.deduplicated.length_fitered.trimmed.fasta"
    log:
        config["output_path"] + "/logs/1_uk_remove_insertions_and_trim.log"
    shell:
        """
        datafunk sam_2_fasta \
          -s {input.sam} \
          -r {input.reference} \
          -o {output.fasta} \
          -t [{params.trim_start}:{params.trim_end}] \
          --log_inserts &> {log}
        mv insertions.txt {params.insertions}
        """

rule uk_filter_low_coverage_sequences:
    input:
        fasta = rules.uk_remove_insertions_and_trim.output.fasta
    params:
        min_covg = config["min_covg"]
    output:
        fasta = config["output_path"] + "/1/uk_latest.unify_headers.epi_week.deduplicated.length_fitered.trimmed.low_covg_filtered.fasta"
    log:
        config["output_path"] + "/logs/1_uk_filter_low_coverage_sequences.log"
    shell:
        """
        datafunk filter_fasta_by_covg_and_length \
          -i {input.fasta} \
          -o {output.fasta} \
          --min_covg {params.min_covg} &> {log}
        """

rule uk_summarize_preprocess:
    input:
        raw_fasta = config["latest_uk_fasta"],
        unify_headers_fasta = rules.uk_unify_headers.output.fasta,
        deduplicated_fasta = rules.uk_remove_duplicates.output.fasta,
        removed_short_fasta = rules.uk_filter_short_sequences.output.fasta,
        removed_low_covg_fasta = rules.uk_filter_low_coverage_sequences.output.fasta
    log:
        config["output_path"] + "/logs/1_summary_preprocess_uk.log"
    shell:
        """
        echo "Number of sequences in raw UK fasta: $(cat {input.raw_fasta} | grep ">" | wc -l)" &> {log}
        echo "Number of sequences in raw UK fasta after unifying headers: $(cat {input.unify_headers_fasta} | grep ">" | wc -l)" &>> {log}
        echo "Number of sequences after deduplication: $(cat {input.deduplicated_fasta} | grep ">" | wc -l)" &>> {log}
        echo "Number of sequences after removing sequences <29000bps: $(cat {input.removed_short_fasta} | grep ">" | wc -l)" &>> {log}
        echo "Number of sequences after trimming and removing those with <95% coverage: $(cat {input.removed_low_covg_fasta} | grep ">" | wc -l)" &>> {log}
        """
