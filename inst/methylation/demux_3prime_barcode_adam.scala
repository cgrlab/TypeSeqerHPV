import org.apache.spark.sql.functions._
import org.apache.spark.SparkContext
import org.bdgenomics.adam.rdd.ADAMContext._
import org.bdgenomics.adam.rdd.read.AlignmentRecordRDD
import org.bdgenomics.adam.sql.AlignmentRecord
import org.bdgenomics.adam.rdd.read.{ AlignmentRecordRDD, AnySAMOutFormatter }
import java.io.File
import sys.process._
import org.apache.spark.sql.SaveMode
import org.apache.spark.sql.expressions.Window
import org.bdgenomics.adam.models._

def getListOfFiles(dir: File, extensions: List[String]): List[File] = {
    dir.listFiles.filter(_.isFile).toList.filter { file =>
        extensions.exists(file.getName.endsWith(_))
    }
}

val barcodes = (spark.read.format("csv").option("header", "true").load("./barcodes.csv")).withColumnRenamed("sequence", "bc_sequence")

object Hamming {
  def compute(s1: String, s2: String): Int = {
    if (s1.length != s2.length)
      throw new IllegalArgumentException()
    (s1.toList).zip(s2.toList)
               .filter(current => current._1 != current._2)
               .length
  }
}

def hamming(sequence: String, bc: String): String = {
Hamming.compute(sequence.takeRight(bc.length()), bc).toString
}

val hammingUDF = udf[String, String, String](hamming)

val splitZA = udf((attributes:String) => {
  if (attributes.contains("ZA")) {attributes.toString.split("ZA:i:").last.split("\t")(0)
}
  else "0"
})

val splitRG = udf((attributes:String) => {
  if (attributes.contains("RG")) {attributes.toString.split("RG:Z:").last.split("\t")(0)
}
  else "0"
})

val replace = udf((data: String , rep : String, newString: String) => {
  data.replaceAll(rep, newString)
})



val readsTransform = sc.loadAlignments("*.bam").transformDataset(df => {

df.toDF().withColumn("oldZA", splitZA($"attributes")).withColumn("ZA", $"oldZA" cast "Int" as "oldZA").withColumn("seqLength", length($"sequence")).filter($"mapq" > 4 and $"ZA" === $"seqLength").join(barcodes, hammingUDF(df("sequence"), barcodes("bc_sequence")) < 1).withColumn("bc1", $"recordGroupSample" cast "String" as "recordGroupSample").withColumn("recordGroupSample", concat(lit("A"), $"recordGroupSample", $"id")).withColumn("recordGroupName", concat($"RecordGroupSample", lit("."), $"recordGroupName")).withColumn("readName", concat($"recordGroupSample", lit(":"), $"readName")).withColumn("oldRG", splitRG($"attributes")).withColumn("attributes", replace($"attributes", $"oldRG", $"recordGroupName")).drop("oldZA", "ZA", "seqLength", "bc1", "oldRG").as[org.bdgenomics.adam.sql.AlignmentRecord]})

val namesList = readsTransform.toDF.select($"recordGroupName").distinct

namesList.repartition(1).write.format("com.databricks.spark.csv").save("sampleNames")

val namesListArray = namesList.rdd.map(r => r(0)).collect()

val tempRGDictionary = RecordGroupDictionary(namesListArray.map(x => new RecordGroup(x.toString.take(6), x.toString, None, None, None, Some("TACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGATCGATGTACAGCTACGTACGTCTGAGCATCGA"))).toSeq)

val programSteps = new org.bdgenomics.formats.avro.ProcessingStep

programSteps.id = "Methyl"
programSteps.programName = "Methylation plugin"

readsTransform.replaceRecordGroups(tempRGDictionary).sort.replaceProcessingSteps(Seq(programSteps)).saveAsSam("demux_reads.bam", asSingleFile=true)


//command to exit spark shell
System.exit(0)


