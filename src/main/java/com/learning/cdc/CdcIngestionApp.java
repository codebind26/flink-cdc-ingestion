package com.learning.cdc;

import org.apache.flink.cdc.cli.parser.PipelineDefinitionParser;
import org.apache.flink.cdc.cli.parser.YamlPipelineDefinitionParser;
import org.apache.flink.cdc.common.configuration.Configuration;
import org.apache.flink.cdc.composer.PipelineExecution;
import org.apache.flink.cdc.composer.definition.PipelineDef;
import org.apache.flink.cdc.composer.flink.FlinkPipelineComposer;
import org.apache.flink.core.fs.Path;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;

public class CdcIngestionApp {

    public static void main(String[] args) throws Exception {
        String yamlPath = args.length > 0 ? args[0]
                : "src/main/resources/yaml_files/ecommerce-pipeline-local.yaml";

        System.out.println("Starting CDC pipeline from: " + yamlPath);

        PipelineDefinitionParser parser = new YamlPipelineDefinitionParser();
        PipelineDef pipelineDef = parser.parse(new Path(yamlPath), new Configuration());
        System.out.println("Parsed pipeline definition");

        // parent-first classloading = single copy of Options = no ClassCastException
        org.apache.flink.configuration.Configuration flinkConf = new org.apache.flink.configuration.Configuration();
        flinkConf.set(org.apache.flink.configuration.CoreOptions.CLASSLOADER_RESOLVE_ORDER, "parent-first");
        flinkConf.set(org.apache.flink.configuration.RestOptions.PORT, 8099);

        // Create a local embedded environment (like MiniCluster but with parent-first)
        StreamExecutionEnvironment env = StreamExecutionEnvironment.createLocalEnvironmentWithWebUI(flinkConf);
        env.enableCheckpointing(30000);
        env.setParallelism(2);

        FlinkPipelineComposer composer = FlinkPipelineComposer.ofApplicationCluster(env);
        PipelineExecution execution = composer.compose(pipelineDef);

        System.out.println("Executing pipeline...");
        execution.execute();
    }
}
