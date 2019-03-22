#+

typing_variant_filter <- function(variants, lineage_defs, manifest,
                                  specimen_control_defs, internal_control_defs,
                                  pn_filters, scailing_table){

    require(fuzzyjoin)

    # add manifest to variants table ----

    variants_with_manifest = manifest %>%
        mutate(barcode = paste0(BC1, BC2)) %>%
        inner_join(variants) %>%
        select(-filename, -BC1, -BC2) %>%
        filter(HS) %>%
        glimpse()

    # make read_counts_matrix ----

    read_counts_matrix_long = variants_with_manifest %>%
        group_by(Owner_Sample_ID, barcode, CHROM) %>%
        summarize(depth = max(DP)) %>%
        group(barcode) %>%
        mutate(total_reads = sum(depth)) %>%
        group_by(barcode, Owner_Sample_ID)


    read_counts_matrix = read_counts_matrix_long %>%
        spread(CHROM, depth) %>%
        glimpse() %>%
        write_csv("read_counts_matrix_results.csv")

    # scale the filters - calculate the average reads per sample ----

    average_total_reads_df = read_counts_matrix %>%
        summarize(average_read_count = mean(total_reads))

    scaling_df = read_csv(scaling_table) %>%
        map_if(is.factor, as.character) %>%
        as_tibble() %>%
        glimpse() %>%
        mutate(average_read_count = average_total_reads_df$average_read_count) %>%
        filter(min_avg_reads_boundary <= average_read_count & max_avg_reads_boundary >= average_read_count) %>%
        glimpse()

    scaling_factor = scaling_df$scaling_factor

    # read in internal controls ----
    internal_control_defs = read_csv(internal_control_defs) %>%
        map_if(is.factor, as.character) %>%
        as_tibble() %>%
        glimpse()  %>%
        gather("type", "control_status", -internal_control_code, -qc_name, -qc_print) %>%
        filter(!(is.na(control_status)))

    # read in pn_filters ----

    pn_filters = read_csv(pn_filters) %>%
        map_if(is.factor, as.character) %>%
        as_tibble() %>%
        glimpse() %>%
        rename(CHROM = contig) %>%
        mutate(Min_reads_per_type = Min_reads_per_type * scaling_factor)


    # make detailed pn matrix ----

    detailed_pn_matrix_long = read_counts_matrix_long %>%
        inner_join(pn_filters)
        mutate(status = ifelse(depth >= Min_reads_per_type, "pos", "neg")) %>%
        glimpse() %>%
        select(-depth) %>%
        left_join(internal_control_defs) %>%
        mutate(control_status_as_num = ifelse(status == control_status,
                                                  0, 1)) %>%
        group_by(several_things) %>%
        mutate(sum_control_status_as_num = sum(control_status_as_num)) %>%
        mutate(qc_print = ifelse(sum_control_status_as_num == 0, qc_print, "Fail"))


    detailed_pn_matrix_long %>%
        spread(CHROM, status) %>%
        glimpse() %>%
        write_csv("detailed_pn_matrix_results.csv")

    # make simple pn matrix ----

    simple_pn_matrix_long = detailed_pn_matrix_long %>%
        separate(CHROM, sep = "_", into = c("type"), remove = FALSE, extra = "drop") %>%
        glimpse() %>%
        mutate(status_as_integer = ifelse(status == "pos", 1, 0)) %>%
        group_by(type) %>%
        mutate(sum_status = sum(status_as_integer)) %>%
        mutate(simple_status = ifelse(status_as_integer >= 1, "pos", "neg")) %>%
        ungroup() %>%
        glimpse() %>%
        select(-status_as_integer, -CHROM, -sum_status, -status) %>%
        distinct() %>%
        glimpse()

    #print simple pn matrix ----
    simple_pn_matrix_long %>%
        spread(type, simple_status) %>%
        glimpse() %>%
        write_csv("pn_matrix_results.csv")





    # read in control defs ----


    specimen_control_defs = specimen_control_defs %>%
        glimpse() %>%
        tidyr::gather("chrom", "min_coverage", -control_code) %>%
        glimpse()

    coverage_matrix %>%
        gather("chrom", "depth", -Owner_Sample_ID, -barcode) %>%
        mutate(depth = as.integer(depth)) %>%
        fuzzy_join(control_defs, mode = "inner", by = c("Owner_Sample_ID" = "control_code"), match_fun = function(x, y) str_detect(x, fixed(y, ignore_case = TRUE))) %>%
        filter(chrom.x == chrom.y) %>%
        mutate(control_result = ifelse(depth >= min_coverage, "pass", "fail")) %>%
        glimpse() %>%
        select(Owner_Sample_ID, barcode, chrom = chrom.x, control_result) %>%
        arrange(Owner_Sample_ID, chrom) %>%
        spread(chrom, control_result) %>%
        write_csv("control_results.csv")











    # ?identify lineages ----
    filteringTable = read_csv(lineage_defs) %>%
        map_if(is.factor, as.character) %>%
        as_tibble() %>%
        rename(CHROM = Chr, POS = Base_num, REF = Base_ID, ALT = vcf_variant)

    filtered_variants = variants %>%
        inner_join(filteringTable) %>%
        mutate(AF = as.double(AF)) %>%
        mutate(qc_reason = "Pass") %>%
        mutate(qc_reason = ifelse(DP >= min_DP, qc_reason,
                                  "min_DP")) %>%
        mutate(qc_reason = ifelse(SRF >= min_coverage_pos, qc_reason,
                                  paste0(qc_reason, ";", "min_coverage_pos"))) %>%
        mutate(qc_reason = ifelse(SRR >= min_coverage_neg, qc_reason,
                                  paste0(qc_reason, ";", "min_coverage_neg"))) %>%
        mutate(qc_reason = ifelse(SAF >= min_allele_coverage_pos, qc_reason,
                                  paste0(qc_reason, ";", "min_allele_coverage_pos"))) %>%
        mutate(qc_reason = ifelse(SAR >= min_allele_coverage_neg, qc_reason,
                                  paste0(qc_reason, ";", "min_allele_coverage_neg"))) %>%
        mutate(qc_reason = ifelse(QUAL >= min_qual, qc_reason,
                                  paste0(qc_reason, ";", "min_qual"))) %>%
        mutate(qc_reason = ifelse(STB <= max_alt_strand_bias, qc_reason,
                                  paste0(qc_reason, ";", "max_alt_strand_bias"))) %>%
        mutate(qc_reason = ifelse(methyl_freq >= min_freq, qc_reason,
                                  paste0(qc_reason, ";", "min_freq"))) %>%
        mutate(qc_reason = ifelse(methyl_freq <= max_freq, qc_reason,
                                  paste0(qc_reason, ";", "max_freq"))) %>%
        mutate(qc_reason = ifelse(FILTER == "PASS", qc_reason,
                                  paste0(qc_reason, ";", FILTER))) %>%
        mutate(status = ifelse(qc_reason == "Pass", "Pass", "Fail")) %>%
        glimpse() %>%
        inner_join(pos_conversion) %>%
        select(chr, pos, DP, methyl_freq, QUAL, status, qc_reason, everything())

    return_table = manifest %>%
        mutate(barcode = paste0(BC1, BC2)) %>%
        left_join(filtered_variants) %>%
        select(-filename, -BC1, -BC2) %>%
        write_csv("target_variants_results.csv")


    return_table %>%
        group_by(Owner_Sample_ID, barcode, chr_amplicon) %>%
        summarize(mean_freq = mean(methyl_freq)) %>%
        ungroup() %>%
        group_by(barcode, Owner_Sample_ID) %>%
        spread(chr_amplicon, mean_freq) %>%
        glimpse() %>%
        write_csv("freq_matrix_results.csv")



}