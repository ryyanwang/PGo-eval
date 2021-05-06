package pgo

import geny.Generator
import org.rogach.scallop
import org.rogach.scallop.{ScallopConf, Subcommand}
import pgo.model.{PGoError, SourceLocation}
import pgo.model.mpcal.MPCalBlock
import pgo.model.tla.TLAModule
import pgo.parser.{MPCalParser, TLAParser}
import pgo.trans.{MPCalGoCodegenPass, MPCalNormalizePass, MPCalPCalCodegenPass, MPCalSemanticCheckPass, PCalRenderPass}

import pgo.util.Description._

import java.io.RandomAccessFile
import java.nio.channels.FileChannel
import java.nio.charset.StandardCharsets
import scala.util.Using

object PGo {
  implicit val pathConverter = scallop.singleArgConverter(os.Path(_, os.pwd))

  class Config(arguments: Seq[String]) extends ScallopConf(arguments) {
    banner("PGo compiler")
    trait Cmd { self: ScallopConf =>
      val specFile = opt[os.Path](required = true)
      addValidation {
        if(os.exists(specFile())) {
          Right(())
        } else {
          Left(s"spec file ${specFile()} does not exist")
        }
      }
    }
    object GoGenCmd extends Subcommand("gogen") with Cmd {
      val outFile = opt[os.Path](required = true)
      val packageName = opt[String](required = false)
    }
    addSubcommand(GoGenCmd)
    object PCalGenCmd extends Subcommand("pcalgen") with Cmd {
      // pass
    }
    addSubcommand(PCalGenCmd)

    // one of the subcommands must be passed
    addValidation {
      subcommand match {
        case Some(_) => Right(())
        case None => Left(s"a subcommand must be given")
      }
    }

    errorMessageHandler = { errMsg =>
      errMsg.linesIterator.foreach { line =>
        println(s"$printedName: $line")
      }
      printHelp()
      sys.exit(1)
    }

    verify()
  }

  private def parseMPCal(specFile: os.Path): (TLAModule, MPCalBlock) = {
    val underlyingFile = new SourceLocation.UnderlyingFile(specFile)
    Using.Manager { use =>
      val fileChannel = use(new RandomAccessFile(specFile.toIO, "r").getChannel)
      val buffer = fileChannel.map(FileChannel.MapMode.READ_ONLY, 0, fileChannel.size)
      val charBuffer = StandardCharsets.UTF_8.decode(buffer)

      val tlaModule = TLAParser.readModuleBeforeTranslation(underlyingFile, charBuffer)
      val mpcalBlock = MPCalParser.readBlock(underlyingFile, charBuffer, tlaModule)
      (tlaModule, mpcalBlock)
    }.get
  }

  def run(args: Seq[String]): List[PGoError.Error] = {
    val config = new Config(args)
    try {
      config.subcommand.get match {
        case config.GoGenCmd =>
          var (tlaModule, mpcalBlock) = parseMPCal(config.GoGenCmd.specFile())
          MPCalSemanticCheckPass(tlaModule, mpcalBlock)
          mpcalBlock = MPCalNormalizePass(tlaModule, mpcalBlock)

          val goCode = MPCalGoCodegenPass(mpcalBlock, packageName = config.GoGenCmd.packageName.toOption)
          os.write(config.GoGenCmd.outFile(), goCode.linesIterator)
        case config.PCalGenCmd =>
          var (tlaModule, mpcalBlock) = parseMPCal(config.PCalGenCmd.specFile())
          MPCalSemanticCheckPass(tlaModule, mpcalBlock)
          mpcalBlock = MPCalNormalizePass(tlaModule, mpcalBlock)

          val pcalAlgorithm = MPCalPCalCodegenPass(mpcalBlock)
          val renderedPCal = PCalRenderPass(pcalAlgorithm)

          val tempOutput = os.temp.apply(dir = os.pwd)
          locally {
            val PCalBeginTranslation = raw"""\\*\s+BEGIN\s+PLUSCAL\s+TRANSLATION""".r
            val PCalEndTranslation = raw"""\\*\s+END\s+PLUSCAL\s+TRANSLATION""".r

            val renderedPCalIterator = Iterator("", "", "\\* BEGIN PLUSCAL TRANSLATION") ++
              renderedPCal.linesIterator ++
              Iterator("", "\\* END PLUSCAL TRANSLATION", "")

            var pcalBeginFound = false
            var pcalEndFound = false

            os.write.over(tempOutput, (os.read.lines.stream(config.PCalGenCmd.specFile()).zipWithIndex.flatMap {
              case (PCalBeginTranslation(), lineIdx) if !pcalBeginFound =>
                assert(!pcalEndFound, s"at line ${lineIdx+1}, found PLUSCAL END TRANSLATION comment before PLUSCAL BEGIN TRANSLATION")
                pcalBeginFound = true
                Generator.from(renderedPCalIterator)
              case (PCalEndTranslation(), lineIdx) =>
                assert(!pcalEndFound, s"at line ${lineIdx+1}, found PLUSCAL END TRANSLATION without corresponding previous PLUSCAL BEGIN TRANSLATION")
                pcalEndFound = true
                Generator()
              case _ if pcalBeginFound && !pcalEndFound =>
                // skip all lines between begin and end of translation
                Generator()
              case (line, _) => Iterator(line)
            } ++ Generator.selfClosing {
              (if(!pcalBeginFound) renderedPCalIterator else Iterator.empty, () => ())
            }).map(line => s"$line\n"))
          }
          // move the rendered output over the spec file, replacing it
          os.move(from = tempOutput, to = config.PCalGenCmd.specFile(), replaceExisting = true, atomicMove = true)
      }
      Nil
    } catch {
      case err: PGoError => err.errors
    }
  }

  def main(args: Array[String]): Unit = {
    val errors = run(args)
    if(errors.nonEmpty) {
      d"failed:${
        errors.view.map(err => d"\n${err.description} at ${err.sourceLocation.longDescription.indented}")
          .flattenDescriptions
      }"
        .linesIterator
        .foreach(System.err.println)
      sys.exit(1)
    }
  }
}
