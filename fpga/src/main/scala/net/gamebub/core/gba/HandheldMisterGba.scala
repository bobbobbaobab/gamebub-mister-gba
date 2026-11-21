package net.gamebub.core.gba

import chisel3._
import chisel3.util._
import _root_.gba.GameBoyPlayer
import lib.audio.AudioFilterChain
import lib.mem._
import lib.mem.sdram.BurstSdramController
import net.gamebub.framework.Core
import net.gamebub.framework.interface._
import xilinx.{MMCM, XpmCdcHandshake, XpmCdcSyncRst}

object HandheldMisterGba {
  // Physical byte addresses in the 32 MiB SDRAM window.
  val RomLimit = 0x1d00000
  val BackupBase = RomLimit
  val BackupSize = 0x20000
  val EwramBase = 0x1d40000
  val StatesBase = 0x1e00000
  val SlotSize = 0x80000
  val StatesSize = SlotSize * 4

  private val VcoHz = (50e6 * 60.375 / 3).toInt
  private val SystemDivider = 12
  private val GbaCycleDivider = 5
  private val ClockHz = VcoHz / SystemDivider
  private val AudioDivider = 3 * SystemDivider
  private val AudioClockHz = VcoHz / AudioDivider
  private val FramePeriod = 308.0 * 228 * 4 * GbaCycleDivider / ClockHz

  private object Transfer extends ChiselEnum {
    val idle, romFirst, romSecond, workRead, workWrite, stateFirst, stateSecond = Value
  }
  private object Snapshot extends ChiselEnum {
    val idle, launch, waitBusy, waitDone = Value
  }
  private object Command extends ChiselEnum {
    val idle, waitForMemory, done, error = Value
  }
}

class HandheldMisterGba extends Module with Core {
  import HandheldMisterGba._

  private val displayDivider = (VcoHz / ClocksV0.getClockDisplayHz(FramePeriod)._1).toInt
  val io = IO(new Bundle {
    val clocks = new ClocksV0(ClockHz, VcoHz / displayDivider, VcoHz / 5)
    val video = new VideoV0(240, 160, 5, 5, 5, FramePeriod, hdmiPillarbox3To2 = true)
    val videoFilter = new VideoFilterBasicV0(5, 5, 5, latency = 3)
    val audio = new AudioV0()
    val host = new HostV0()
    val input = new InputV0()
    val vibrate = new VibrateV0()
    val sdram = new SdramV0()
  })

  val mmcm = Module(new MMCM(50_000_000, 3, 60.375, Seq(
    MMCM.ClockOut(SystemDivider), MMCM.ClockOut(displayDivider), MMCM.ClockOut(5), MMCM.ClockOut(AudioDivider),
  )))
  mmcm.io.clockIn := io.clocks.clockIn50M
  mmcm.io.powerDown := false.B
  io.clocks.clockOutSystem := mmcm.io.clockOuts(0)
  io.clocks.clockOutDisplay := mmcm.io.clockOuts(1)
  io.clocks.clockOutSpi := mmcm.io.clockOuts(2)
  io.clocks.locked := mmcm.io.locked

  val core = Module(new MisterGba(GbaCycleDivider))
  val gba = core.io
  gba.clk := clock
  val setup = RegInit(false.B)
  val running = RegInit(false.B)
  val focused = RegInit(false.B)
  val romWords = RegInit(0.U(25.W))
  val romUpload = RegInit(false.B)
  val flash1m = RegInit(false.B)
  val romTail = RegInit(0.U(64.W))

  val memory = Module(new BurstSdramController(BurstSdramController.Config(
    clockFrequency = ClockHz,
    // Allow 20 ns for both SDRAM activation and precharge.
    timeRcd = 20,
    timeRp = 20,
    // Account for the controller using an 11 ns integer clock period.
    timeRef = 59_000_000,
  )))
  val arbiter = Module(new PipelineMemoryArbiter(addressWidth = 25, dataWidth = 32, n = 2))
  memory.io.mem <> arbiter.io.target
  io.sdram.clock := clock
  io.sdram.cke := memory.io.signals.cke
  io.sdram.cs := memory.io.signals.cs
  io.sdram.ras := memory.io.signals.ras
  io.sdram.cas := memory.io.signals.cas
  io.sdram.we := memory.io.signals.we
  io.sdram.dqm := memory.io.signals.dqm
  io.sdram.bank := memory.io.signals.bank
  io.sdram.address := memory.io.signals.address
  io.sdram.dataOut := memory.io.signals.dataOut
  io.sdram.dataDir := memory.io.signals.dataDir
  memory.io.signals.dataIn := io.sdram.dataIn

  val hostBridge = Module(new PipelineInterfaceBridge(addressWidth = 25, dataWidth = 32))
  val coreBridge = Module(new PipelineInterfaceBridge(addressWidth = 25, dataWidth = 32))
  arbiter.io.initiator(0) <> coreBridge.io.dest
  arbiter.io.initiator(1) <> hostBridge.io.dest
  val bus = coreBridge.io.source

  val registers = Wire(new MemoryInterface(16, 32))
  val bios = Wire(new MemoryInterface(14, 32))
  val commands = Wire(new MemoryInterface(16, 32))
  val hostMemory = MemoryMap(32, 32, Seq(
    0x0.U(4.W) -> registers,
    0x1.U(4.W) -> bios,
    0x3.U(4.W) -> hostBridge.io.source,
    0xf0.U(8.W) -> commands,
  ))
  io.host.mem.unsafe :<>= hostMemory.unsafe
  hostMemory.writeStrobe := "b1111".U
  gba.bios_address := bios.address(13, 2)
  gba.bios_data := bios.dataWrite
  gba.bios_write := bios.enable && bios.write && !running
  bios.done := true.B
  bios.dataRead := 0.U

  // Scan all byte alignments, including signatures that straddle SPI words.
  when (romUpload && hostBridge.io.source.done && hostBridge.io.source.write) {
    val word = hostBridge.io.source.dataWrite
    val bytes = Cat(romTail, word(7, 0), word(15, 8), word(23, 16), word(31, 24))
    romTail := bytes(63, 0)
    val signature = BigInt("464c415348314d5f56", 16).U(72.W) // FLASH1M_V
    when ((0 until 4).map(i => bytes(71 + 8*i, 8*i) === signature).reduce(_ || _)) {
      flash1m := true.B
    }
  }
  gba.flash_1m := flash1m
  gba.rom_words := romWords

  // Upstream requests the addressed ROM dword first, then its partner in the
  // same aligned pair. The partner must be valid on the cycle after rom_done.
  private val transfer = RegInit(Transfer.idle)
  val address = Reg(UInt(25.W))
  val writeData = Reg(UInt(64.W))
  val read = Reg(Bool())
  val backup = Reg(Bool())
  val byteLane = Reg(UInt(2.W))
  val firstWord = Reg(UInt(32.W))
  val romFirst = Reg(UInt(32.W))
  val romSecond = Reg(UInt(32.W))
  val workResult = Reg(UInt(32.W))
  val stateResult = Reg(UInt(64.W))
  val romDone = RegInit(false.B)
  val workDone = RegInit(false.B)
  val stateDone = RegInit(false.B)
  val stateHeaderWritten = WireDefault(false.B)

  gba.rom_first := romFirst
  gba.rom_second := romSecond
  gba.rom_done := romDone
  gba.work_read_data := workResult
  gba.work_done := workDone
  gba.state_read_data := stateResult
  gba.state_done := stateDone
  romDone := false.B
  workDone := false.B
  stateDone := false.B

  bus.enable := transfer =/= Transfer.idle
  bus.address := address
  bus.write := false.B
  bus.writeStrobe := "b1111".U
  bus.dataWrite := writeData(31, 0)

  // Each upstream port emits a one-cycle request and waits for its own
  // acknowledgment. Keep the full request if another port owns the bus.
  val pendingRom = RegInit(false.B)
  val pendingWork = RegInit(false.B)
  val pendingState = RegInit(false.B)
  val romAddress = RegEnable(gba.rom_address, gba.rom_request)
  val workAddress = RegEnable(gba.work_address, gba.work_request)
  val workRead = RegEnable(gba.work_read, gba.work_request)
  val workData = RegEnable(gba.work_write_data, gba.work_request)
  val stateAddress = RegEnable(gba.state_address, gba.state_request)
  val stateRead = RegEnable(gba.state_read, gba.state_request)
  val stateData = RegEnable(gba.state_write_data, gba.state_request)
  when (gba.rom_request) { pendingRom := true.B }
  when (gba.work_request) { pendingWork := true.B }
  when (gba.state_request) { pendingState := true.B }

  switch (transfer) {
    is (Transfer.idle) {
      // Work RAM writes are full dwords. Cartridge storage uses one dword
      // address per byte in MiSTer and is packed into a normal file here.
      when (pendingWork) {
        val isBackup = !workAddress(17)
        val workOffset = workAddress(15, 0) << 2
        address := Mux(isBackup, BackupBase.U + (workAddress(16, 0) & "h1fffc".U),
          EwramBase.U + workOffset)
        byteLane := workAddress(1, 0)
        writeData := workData
        read := workRead
        backup := isBackup
        transfer := Mux(workRead || isBackup, Transfer.workRead, Transfer.workWrite)
        pendingWork := false.B
      } .elsewhen (pendingState) {
        address := StatesBase.U + (stateAddress(18, 0) << 2)
        writeData := stateData
        read := stateRead
        transfer := Transfer.stateFirst
        pendingState := false.B
      } .elsewhen (pendingRom) {
        address := romAddress(22, 0) << 2
        transfer := Transfer.romFirst
        pendingRom := false.B
      }
    }
    is (Transfer.romFirst) {
      when (bus.done) {
        firstWord := bus.dataRead
        address := address ^ 4.U
        transfer := Transfer.romSecond
      }
    }
    is (Transfer.romSecond) {
      when (bus.done) {
        romFirst := firstWord
        romSecond := bus.dataRead
        romDone := true.B
        transfer := Transfer.idle
      }
    }
    is (Transfer.workRead) {
      when (bus.done) {
        when (read) {
          workResult := Mux(backup, bus.dataRead.asTypeOf(Vec(4, UInt(8.W)))(byteLane), bus.dataRead)
          workDone := true.B
          transfer := Transfer.idle
        } .otherwise {
          val bytes = Wire(Vec(4, UInt(8.W)))
          bytes := bus.dataRead.asTypeOf(bytes)
          bytes(byteLane) := writeData(7, 0)
          writeData := bytes.asUInt
          transfer := Transfer.workWrite
        }
      }
    }
    is (Transfer.workWrite) {
      bus.write := true.B
      when (bus.done) {
        workDone := true.B
        transfer := Transfer.idle
      }
    }
    is (Transfer.stateFirst) {
      bus.write := !read
      when (bus.done) {
        firstWord := bus.dataRead
        address := address + 4.U
        transfer := Transfer.stateSecond
      }
    }
    is (Transfer.stateSecond) {
      bus.write := !read
      bus.dataWrite := writeData(63, 32)
      when (bus.done) {
        stateHeaderWritten := !read && address(log2Ceil(SlotSize) - 1, 0) === 4.U
        stateResult := Cat(bus.dataRead, firstWord)
        stateDone := true.B
        transfer := Transfer.idle
      }
    }
  }

  val slot = RegInit(0.U(2.W))
  val colorProfile = RegInit(1.U(3.W))
  val gameBoyPlayerEnabled = RegInit(true.B)
  val activeSlot = RegInit(0.U(2.W))
  private val snapshot = RegInit(Snapshot.idle)
  val save = Reg(Bool())
  val snapshotSuccess = RegInit(false.B)
  val snapshotResult = RegInit(0.U(2.W))
  val snapshotActive = snapshot =/= Snapshot.idle
  val exporting = RegInit(false.B)
  // A power-off export can arrive while the game has focus. Allow the CPU
  // pause to take effect and let already-issued memory transactions drain.
  val exportDrain = RegInit(0.U(8.W))
  when (exportDrain =/= 0.U) { exportDrain := exportDrain - 1.U }

  val buttons = io.input.buttons
  val inputActive = running && focused && !snapshotActive && !exporting
  val savePressed = buttons.x && !RegNext(buttons.x, false.B)
  val loadPressed = buttons.y && !RegNext(buttons.y, false.B)
  // Use the same request as the Home menu. A register write takes priority.
  val request = WireDefault(0.U(2.W))
  when (inputActive && loadPressed) {
    request := 2.U
  } .elsewhen (inputActive && savePressed) {
    request := 1.U
  }

  registers <> RegisterMap(16, 32, Seq(
    0x0014 -> RegisterMap.Entry.w(request),
    0x0018 -> RegisterMap.Entry.rw(slot),
    0x001c -> RegisterMap.Entry.r(snapshotResult),
    0x0020 -> RegisterMap.Entry.rw(colorProfile),
    0x0028 -> RegisterMap.Entry.rw(gameBoyPlayerEnabled),
  ))

  gba.run := (running || snapshotActive) && romWords =/= 0.U
  gba.pause := !snapshotActive && (!focused || exporting)
  gba.state_slot := activeSlot
  // Wait for the engine to finish any startup reset before watching for busy.
  val launchSnapshot = snapshot === Snapshot.launch && !gba.state_busy
  gba.state_save := launchSnapshot && save
  gba.state_load := launchSnapshot && !save

  when (stateHeaderWritten || gba.state_loaded) { snapshotSuccess := true.B }
  switch (snapshot) {
    is (Snapshot.idle) {
      when (running && !exporting && romWords =/= 0.U && request =/= 0.U && request =/= 3.U) {
        activeSlot := slot
        save := request === 1.U
        snapshotResult := 1.U
        snapshotSuccess := false.B
        snapshot := Snapshot.launch
      }
    }
    is (Snapshot.launch) {
      when (launchSnapshot) { snapshot := Snapshot.waitBusy }
    }
    is (Snapshot.waitBusy) {
      when (gba.state_busy) { snapshot := Snapshot.waitDone }
    }
    is (Snapshot.waitDone) {
      when (!gba.state_busy) {
        snapshotResult := Mux(snapshotSuccess || gba.state_loaded, 2.U, 3.U)
        snapshot := Snapshot.idle
      }
    }
  }

  private val commandState = RegInit(Command.idle)
  val commandWords = RegInit(VecInit.fill(4)(0.U(32.W)))
  commands <> RegisterMap(16, 32, commandWords.zipWithIndex.map { case (word, i) =>
    i * 4 -> RegisterMap.Entry.rw(word)
  })
  val fileId = commandWords(1)(15, 0)
  val fileBytes = commandWords(2)
  val exportSize = Reg(UInt(32.W))
  io.host.commandHost.busy := commandState === Command.waitForMemory
  io.host.commandHost.done := commandState === Command.done
  io.host.commandHost.error := commandState === Command.error
  io.host.commandCore.request := false.B

  when (!io.host.commandHost.request) {
    commandState := Command.idle
  } .elsewhen (commandState === Command.idle) {
    commandWords(0) := 0.U
    commandState := Command.done
    switch (commandWords(0)(15, 0)) {
      is (HostV0.CommandGetStatus.U) {
        commandWords(0) := Mux(!setup, HostV0.StatusSetup.U,
          Mux(running, HostV0.StatusCoreRun.U, HostV0.StatusCoreHalt.U))
      }
      is (HostV0.CommandSetupComplete.U) { setup := true.B }
      is (HostV0.CommandCoreRun.U) { running := true.B }
      is (HostV0.CommandCoreHalt.U) { running := false.B }
      is (HostV0.CommandNotifyFocus.U) { focused := commandWords(1)(0) }
      is (HostV0.CommandFileWriteStart.U) {
        when (fileId === 0.U) {
          romUpload := true.B
          romWords := 0.U
          romTail := 0.U
          flash1m := false.B
        }
      }
      is (HostV0.CommandFileWriteEnd.U) {
        when (fileId === 0.U) {
          romUpload := false.B
          when (fileBytes >= 192.U && fileBytes <= RomLimit.U) {
            romWords := (fileBytes + 3.U) >> 2
          } .otherwise {
            commandState := Command.error
          }
        }
      }
      is (HostV0.CommandFileReadStart.U) {
        when (fileId === 1.U || fileId === 3.U) {
          exportSize := Mux(fileId === 1.U, BackupSize.U, StatesSize.U)
          exporting := true.B
          exportDrain := 255.U
          commandState := Command.waitForMemory
        } .otherwise {
          commandState := Command.error
        }
      }
      is (HostV0.CommandFileReadEnd.U) { exporting := false.B }
    }
  } .elsewhen (commandState === Command.waitForMemory) {
    when (exportDrain === 0.U && !snapshotActive && transfer === Transfer.idle && !pendingRom && !pendingWork && !pendingState &&
      !gba.rom_request && !gba.work_request && !gba.state_request) {
      commandWords(0) := exportSize
      commandState := Command.done
    }
  }

  // Game Bub's framebuffer consumes a raster stream. The upstream core
  // emits pixels in bursts, with the position of each emitted pixel.
  val frameStart = gba.pixel_x === 0.U && gba.pixel_y === 0.U
  val frameValid = RegInit(false.B)
  val videoReset = !gba.run || gba.state_loaded
  val pixel = gba.pixel_write && !videoReset && (frameValid || frameStart)
  val endOfLine = pixel && gba.pixel_x === 239.U
  val endOfFrame = endOfLine && gba.pixel_y === 159.U
  when (videoReset || endOfFrame) {
    frameValid := false.B
  } .elsewhen (pixel && frameStart) {
    frameValid := true.B
  }
  io.video.dataEnable := pixel
  io.video.hblank := RegNext(endOfLine && !endOfFrame, false.B)
  io.video.vblank := RegNext(endOfFrame || videoReset, true.B)
  io.video.data.r := gba.pixel_data(17, 13)
  io.video.data.g := gba.pixel_data(11, 7)
  io.video.data.b := gba.pixel_data(5, 1)
  GbaColorCorrection.setup(clock, colorProfile, io.videoFilter)

  val playerEnabled = gameBoyPlayerEnabled && gba.run
  val player = withReset(reset.asBool || !playerEnabled) {
    Module(new GameBoyPlayer(serialClockDivider = GbaCycleDivider))
  }
  // The detector consumes a complete raw raster, before any color correction.
  player.io.enable := playerEnabled && inputActive
  player.io.ppu.pixel := Cat(io.video.data.b, io.video.data.g, io.video.data.r)
  player.io.ppu.valid := pixel
  player.io.ppu.hblank := RegNext(endOfLine, false.B)
  player.io.ppu.vblank := RegNext(io.video.vblank, false.B)
  player.io.link.in := DontCare
  player.io.link.in.so := gba.gbp_so
  gba.gbp_enable := playerEnabled && (player.io.doKeypadOverride || player.io.doLinkOverride)
  gba.gbp_sc := !player.io.doLinkOverride || player.io.link.out.sc
  gba.gbp_si := !player.io.doLinkOverride || player.io.link.out.si

  val keys = Cat(buttons.l, buttons.r, buttons.down, buttons.up,
    buttons.left, buttons.right, buttons.start, buttons.select, buttons.b, buttons.a)
  gba.keys := Mux(inputActive, Mux(playerEnabled && player.io.doKeypadOverride,
    player.io.keypadOverride, keys), 0.U)
  io.vibrate.mode := Mux(inputActive && (gba.rumble || (playerEnabled && player.io.rumble)),
    VibrateV0.Mode.On, VibrateV0.Mode.Off)

  // Sample the mixer on the related divide-by-three MMCM clock.
  // Vivado times the crossing from these source registers directly.
  val rawAudio = RegNext(VecInit(
    Mux(inputActive, gba.audio_left, 0.S), Mux(inputActive, gba.audio_right, 0.S),
  ))
  val audioClock = mmcm.io.clockOuts(3)
  val audioReset = withClock(audioClock) { XpmCdcSyncRst(reset) }
  val filteredAudio = withClockAndReset(audioClock, audioReset) {
    val audio = Module(new AudioFilterChain(inputRateHz = AudioClockHz, cicR = AudioClockHz / (4 * 48000)))
    audio.io.in := RegNext(rawAudio)
    audio.io.out
  }
  val outputAudio = XpmCdcHandshake.continuous(audioClock, filteredAudio)
  io.audio.left := outputAudio(0)
  io.audio.right := outputAudio(1)
}
