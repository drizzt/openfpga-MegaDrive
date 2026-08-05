// Pads every frame out to the nearest snap point with black lines, so the height
// announced to the scaler always matches the height emitted. From agg23's
// openfpga-SNES, rtl/mister_top/scanline_filler.sv
module scanline_filler #(
    parameter int SNAP_COUNT = 1,
    parameter int SNAP_POINTS[SNAP_COUNT] = '{240},
    parameter int HSYNC_DELAY = 6
) (
    input wire clk,

    input wire hsync_in,
    input wire vsync_in,

    input wire vblank_in,
    input wire hblank_in,

    // pocket: Hide Overscan, which upstream has no equivalent of
    input wire crop_en,
    // pocket-end

    input wire [23:0] rgb_in,

    output reg  hsync,
    output wire vsync,

    output reg de,
    output reg [23:0] rgb,
    output wire [7:0] snap_index,
    output wire [8:0] snap_point
);
  reg prev_de = 0;
  reg prev_hsync = 0;
  reg prev_vsync = 0;
  reg [2:0] hs_delay = 0;

  reg [8:0] output_line_count = 0;
  reg [8:0] visible_line_count = 0;
  // reg [9:0] clks_since_hsync_count = 0;
  // reg [8:0] black_pixel_count = 0;

  reg drawing_line = 0  /* synthesis noprune */;
  reg drawing_black = 0  /* synthesis noprune */;

  wire extended_vblank = vblank_in && ~(output_line_count < snap_point && output_line_count > 0)  /* synthesis keep */;
  wire de_blanks = ~(hblank_in || extended_vblank);

  // pocket: CROP_LINES: rows blanked per edge for Hide Overscan, 8 covering Virtua Racing's
  // flicker. crop_end is latched already subtracted: snap_point still reads 224 into line 225
  // of a 240 line frame, so a live compare blanks 216-224 mid-picture and adds to the rgb path
  localparam int CROP_LINES = 8;

  reg [8:0] crop_end = '1;

  wire crop_row = crop_en && (output_line_count < CROP_LINES[8:0] ||
                              output_line_count >= crop_end);
  // pocket-end

  always @(posedge clk) begin
    prev_hsync <= hsync_in;
    prev_vsync <= vsync_in;
    prev_de <= de_blanks;

    hsync <= 0;
    de <= 0;
    rgb <= 0;
    // clks_since_hsync_count <= clks_since_hsync_count + 1;

    if (vsync_in && ~prev_vsync) begin
      // Reset line count on start of vsync
      output_line_count  <= 0;
      visible_line_count <= 0;
      // pocket: the instant core_top latches snap_index for the scaler slot too
      crop_end <= snap_point - CROP_LINES[8:0];
      // pocket-end
    end

    if (de_blanks && ~prev_de) begin
      // We're drawing on this line
      drawing_line  <= 1;
      drawing_black <= 0;
    end
    // else if (output_line_count < snap_point && ~drawing_line &&
    //              clks_since_hsync_count > CLKS_UNTIL_BLANK_LINE[9:0] &&
    //              black_pixel_count < horizontal_width) begin
    //   // No data to render for this line, but we haven't met the snap point, so fill black
    //   de <= 1;
    //   rgb <= 0;
    //   black_pixel_count <= black_pixel_count + 1;
    //   drawing_black <= 1;
    // end

    if (de_blanks) begin
      de <= 1;
      if (vblank_in) begin
        // Extended blanking
        drawing_black <= 1;
      end
      // pocket: folded into the padding rows' mux, a second 24-bit mux costs 24 ALUTs the SVP
      // fit lacks. drawing_black stays on vblank_in so a blanked row still counts as visible
      rgb <= (vblank_in || crop_row) ? 24'd0 : rgb_in;
      // pocket-end
    end else if (~de_blanks && prev_de) begin
      // Falling edge of drawing
      output_line_count <= output_line_count + 1;
      if (~drawing_black) begin
        // If we drew black this line, it's not visible
        visible_line_count <= visible_line_count + 1;
      end
    end

    // Move hsync to not collide with vsync
    // ------------
    if (hs_delay > 0) begin
      hs_delay <= hs_delay - 1;
    end

    if (hs_delay == 1) begin
      hsync <= 1;
      // clks_since_hsync_count <= 0;
      // black_pixel_count <= 0;
      // drawing_black <= 0;
      drawing_line <= 0;
    end

    if (hsync_in && ~prev_hsync) begin
      if (HSYNC_DELAY <= 1) begin
        hsync <= 1;
        // clks_since_hsync_count <= 0;
        // black_pixel_count <= 0;
        // drawing_black <= 0;
        drawing_line <= 0;
      end else begin
        hs_delay <= HSYNC_DELAY[2:0];
      end
    end
  end

  always @(posedge clk) begin
    for (int i = 0; i < SNAP_COUNT; i = i + 1) begin
      if (visible_line_count <= SNAP_POINTS[i][8:0]) begin
        snap_index <= i[7:0];
        snap_point <= SNAP_POINTS[i][8:0];
      end
    end

  end

  assign vsync = vsync_in && ~prev_vsync;

endmodule
