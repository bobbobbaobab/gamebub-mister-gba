package net.gamebub.framework.interface

import chisel3._
import chisel3.util._
import lib.video.ColorRGB

class VideoV0(
  /// Width of the video output, in pixels
  val videoWidth: Int,
  /// Height of the video output, in pixels
  val videoHeight: Int,
  /// Bits per pixel for the R channel.
  val colorDepthR: Int,
  /// Bits per pixel for the G channel.
  val colorDepthG: Int,
  /// Bits per pixel for the B channel.
  val colorDepthB: Int,
  /// Target frame period, in seconds.
  val framePeriod: Double,
  /// Center a 3:2 picture in the dock's 480p output for a 16:9 TV.
  val hdmiPillarbox3To2: Boolean = false,
) extends Bundle {
  val data = Output(ColorRGB.apply(colorDepthR, colorDepthG, colorDepthB))
  val dataEnable = Output(Bool())
  val vblank = Output(Bool())
  val hblank = Output(Bool())
}
