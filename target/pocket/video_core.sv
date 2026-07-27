// Raster output adapter for the Pocket scaler. Feed it RGB888 and one pixel per clk_vid

`default_nettype none

module video_core (
    input wire clk_sys,
    input wire clk_vid,

    input wire [23:0] rgb,
    input wire        hs,
    input wire        vs,
    input wire        hblank,
    input wire        vblank,
    input wire [ 2:0] scaler_slot,

    output reg  [23:0] video_rgb = 0,
    output reg         video_de = 0,
    output reg         video_hs = 0,
    output reg         video_vs = 0,
    output wire        video_skip
);

  assign video_skip = 1'b0;

  reg [23:0] rgb_r = 0;
  reg        hs_r = 0;
  reg        vs_r = 0;
  reg        hblank_r = 0;
  reg        vblank_r = 0;
  reg [ 2:0] slot_r = 0;

  // Re-register in clk_sys first so the cross-domain path is reg to reg
  always @(posedge clk_sys) begin
    rgb_r    <= rgb;
    hs_r     <= hs;
    vs_r     <= vs;
    hblank_r <= hblank;
    vblank_r <= vblank;
    slot_r   <= scaler_slot;
  end

  reg prev_hs = 0;
  reg prev_vs = 0;

  always @(posedge clk_vid) begin
    prev_hs  <= hs_r;
    prev_vs  <= vs_r;

    video_de <= ~(hblank_r | vblank_r);

    if (~(hblank_r | vblank_r)) begin
      video_rgb <= rgb_r;
    end else if (video_de) begin
      // First blanking cycle after DE falls carries function code 0 on [23:13], the
      // scaler slot: the Pocket scaler never measures the DE window itself
      video_rgb <= {8'd0, slot_r, 13'd0};
    end else begin
      video_rgb <= 24'd0;
    end

    video_hs <= hs_r & ~prev_hs;
    video_vs <= vs_r & ~prev_vs;
  end

endmodule
