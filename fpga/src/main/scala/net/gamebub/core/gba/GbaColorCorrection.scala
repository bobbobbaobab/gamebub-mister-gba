package net.gamebub.core.gba

import chisel3._
import chisel3.util._
import lib.video.ColorCorrection
import net.gamebub.framework.interface.VideoFilterBasicV0
import xilinx.XpmCdcHandshake

private[gba] object GbaColorCorrection {
  private val inputDepth = 5
  private val outputDepth = 8
  private val internalDepth = 12
  private val matrixDepth = 12
  private val outputTableDepth = 10

  private case class Profile(gamma: Float, luminance: Float, matrix: Seq[Float])

  // Game Bub firmware presets, in the same order as its GBA menu.
  // The correction matrices are credited upstream to Pokefan531 and hunterk.
  private val profiles = Seq(
    Profile(2.2f, 0.91f, Seq(
      0.905f, 0.195f, -0.1f,
      0.1f, 0.65f, 0.25f,
      0.1575f, 0.1425f, 0.7f,
    )),
    Profile(2.2f, 0.935f, Seq(
      0.96f, 0.11f, -0.07f,
      0.0325f, 0.89f, 0.0775f,
      0.001f, -0.03f, 1.029f,
    )),
    Profile(2.2f, 0.905f, Seq(
      0.835f, 0.27f, -0.105f,
      0.1f, 0.6375f, 0.2625f,
      0.105f, 0.175f, 0.72f,
    )),
    Profile(2.2f, 0.935f, Seq(
      0.93f, 0.14f, -0.07f,
      0.025f, 0.90f, 0.075f,
      0.008f, -0.03f, 1.022f,
    )),
    Profile(3.0f, 1.0f, Seq(
      0.865f, 0.1225f, 0.0125f,
      0.0575f, 0.925f, 0.0125f,
      0.0575f, 0.1225f, 0.82f,
    )),
  )

  private def gammaTable(addressDepth: Int, dataDepth: Int, gamma: Float, luminance: Float): Seq[Int] = {
    val lastAddress = (1 << addressDepth) - 1
    val scale = 1 << dataDepth
    (0 to lastAddress).map { i =>
      val linear = math.pow(i.toFloat / lastAddress, gamma).toFloat
      math.min((linear * luminance * scale).toInt, scale - 1)
    }
  }

  def setup(sourceClock: Clock, profile: UInt, filter: VideoFilterBasicV0): Unit = {
    withClockAndReset(filter.clock, filter.reset) {
      val selected = XpmCdcHandshake.continuous(sourceClock, profile)
      val matrixProfile = RegNext(selected, 0.U)
      val corrector = Module(new ColorCorrection(
        inputDepth = inputDepth,
        outputDepth = outputDepth,
        internalDepth = internalDepth,
        matrixDepth = matrixDepth,
        outputTableDepth = outputTableDepth,
      ))
      corrector.io.enable := true.B
      corrector.io.in := filter.dataIn

      val inputTables = profiles.map { p =>
        VecInit(gammaTable(inputDepth, internalDepth, p.gamma, p.luminance)
          .map(_.S((internalDepth + 1).W)))
      }
      val matrices = profiles.map { p =>
        VecInit(p.matrix.map(c => (c * (1 << matrixDepth)).toInt.S((matrixDepth + 2).W)))
      }
      corrector.io.inputTable := MuxLookup(selected, inputTables.head)(
        inputTables.zipWithIndex.map { case (table, i) => (i + 1).U -> table }
      )
      val matrix = MuxLookup(matrixProfile, matrices.head)(
        matrices.zipWithIndex.map { case (coefficients, i) => (i + 1).U -> coefficients }
      )
      corrector.io.matrixR := VecInit(matrix.take(3))
      corrector.io.matrixG := VecInit(matrix.slice(3, 6))
      corrector.io.matrixB := VecInit(matrix.drop(6))

      for (port <- corrector.io.outputTable) {
        val outputGamma = Module(new GbaOutputGamma)
        outputGamma.io.clk := filter.clock
        outputGamma.io.address := port.address
        port.data := outputGamma.io.data
      }

      val enabled = selected =/= 0.U && selected <= profiles.size.U
      val corrected = ShiftRegister(enabled, filter.latency, false.B, true.B)
      val raw = ShiftRegister(filter.dataIn, filter.latency)
      filter.dataOut := Mux(corrected, corrector.io.out, raw.convertTo(filter.dataOut))
    }
  }

  // The corrected profiles share one output curve. Use a synchronous ROM
  // so Vivado can map it to block RAM and preserve the filter's third stage.
  private class GbaOutputGamma extends ExtModule {
    val io = FlatIO(new Bundle {
      val clk = Input(Clock())
      val address = Input(UInt(outputTableDepth.W))
      val data = Output(UInt(outputDepth.W))
    })

    private val values = gammaTable(outputTableDepth, outputDepth, 1.0f / 2.2f, 1.0f)
    private val init = values.zipWithIndex.map { case (value, i) => s"    rom[$i] = 8'd$value;" }
    setInline("GbaOutputGamma.sv",
      s"""module GbaOutputGamma (
         |  input clk,
         |  input [9:0] address,
         |  output reg [7:0] data
         |);
         |  (* rom_style = "block" *) reg [7:0] rom [0:1023];
         |  initial begin
         |${init.mkString("\n")}
         |  end
         |  always @(posedge clk) data <= rom[address];
         |endmodule
         |""".stripMargin)
  }
}
