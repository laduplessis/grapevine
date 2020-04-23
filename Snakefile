configfile: workflow.current_basedir + "/config.yaml"

import datetime

date = datetime.date.today()

##### Configuration #####

if config.get("output_path"):
    config["output_path"] = config["output_path"].rstrip("/") + "/analysis"
else:
    config["output_path"] = "analysis"

if config.get("publish_path"):
    config["publish_path"] = config["publish_path"].rstrip("/") + "/publish"
else:
    config["publish_path"] = "publish"

##### Target rules #####

rule all:
    input:
        config["output_path"] + "/3/cog_gisaid.fasta",
        config["output_path"] + "/3/cog_gisaid.csv",
        config["output_path"] + "/4/split_done",
        config["output_path"] + "/4/trees_done"

##### Modules #####
include: "rules/0_preprocess_gisaid.smk"
include: "rules/1_preprocess_uk.smk"
include: "rules/2_pangolin_lineage_typing.smk"
include: "rules/3_combine_gisaid_and_uk.smk"
include: "rules/4_make_trees.smk"
