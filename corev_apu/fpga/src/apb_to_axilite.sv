// apb_to_axilite.sv — Adaptateur APB esclave → AXI-Lite maître (32 bits)
//
// Utilisation : pont entre axi2apb_64_32 et xlnx_axi_hwicap.
// APB et AXI-Lite sont fonctionnellement identiques ; seul le protocole
// de handshake diffère (APB : 2 phases SETUP/ACCESS ; AXI-Lite : canaux
// indépendants AW/W/B et AR/R).
//
// Machine d'états :
//   IDLE      : attente de psel & penable (phase ACCESS APB)
//   WR_ACTIVE : pilote awvalid + wvalid ; attend awready et wready
//   WR_RESP   : attend bvalid, termine la transaction APB (pready=1)
//   RD_ACTIVE : pilote arvalid ; attend arready
//   RD_DATA   : attend rvalid, capture rdata, termine (pready=1)

module apb_to_axilite #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32
)(
    input  logic                      clk_i,
    input  logic                      rst_ni,

    // APB esclave (venant de axi2apb_64_32)
    input  logic                      psel_i,
    input  logic                      penable_i,
    input  logic                      pwrite_i,
    input  logic [ADDR_WIDTH-1:0]     paddr_i,
    input  logic [DATA_WIDTH-1:0]     pwdata_i,
    output logic [DATA_WIDTH-1:0]     prdata_o,
    output logic                      pready_o,
    output logic                      pslverr_o,

    // AXI-Lite maître (vers xlnx_axi_hwicap)
    output logic [ADDR_WIDTH-1:0]     awaddr_o,
    output logic                      awvalid_o,
    input  logic                      awready_i,

    output logic [DATA_WIDTH-1:0]     wdata_o,
    output logic [DATA_WIDTH/8-1:0]   wstrb_o,
    output logic                      wvalid_o,
    input  logic                      wready_i,

    input  logic [1:0]                bresp_i,
    input  logic                      bvalid_i,
    output logic                      bready_o,

    output logic [ADDR_WIDTH-1:0]     araddr_o,
    output logic                      arvalid_o,
    input  logic                      arready_i,

    input  logic [DATA_WIDTH-1:0]     rdata_i,
    input  logic [1:0]                rresp_i,
    input  logic                      rvalid_i,
    output logic                      rready_o
);

    typedef enum logic [2:0] {
        IDLE, WR_ACTIVE, WR_RESP, RD_ACTIVE, RD_DATA
    } state_t;

    state_t                  state_q, state_d;
    logic [DATA_WIDTH-1:0]   rdata_q;
    logic                    aw_done_q, w_done_q;

    // Registres d'état
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q   <= IDLE;
            rdata_q   <= '0;
            aw_done_q <= 1'b0;
            w_done_q  <= 1'b0;
        end else begin
            state_q <= state_d;
            // Capture RDATA quand disponible
            if (rvalid_i && rready_o)
                rdata_q <= rdata_i;
            // Suivi handshake AW/W (peuvent arriver dans n'importe quel ordre)
            if (state_q == IDLE) begin
                aw_done_q <= 1'b0;
                w_done_q  <= 1'b0;
            end else begin
                if (awvalid_o && awready_i) aw_done_q <= 1'b1;
                if (wvalid_o  && wready_i)  w_done_q  <= 1'b1;
            end
        end
    end

    // Logique combinatoire
    always_comb begin
        state_d   = state_q;
        pready_o  = 1'b0;
        pslverr_o = 1'b0;
        prdata_o  = rdata_q;

        awaddr_o  = paddr_i;
        awvalid_o = 1'b0;
        wdata_o   = pwdata_i;
        wstrb_o   = '1;
        wvalid_o  = 1'b0;
        bready_o  = 1'b0;

        araddr_o  = paddr_i;
        arvalid_o = 1'b0;
        rready_o  = 1'b0;

        case (state_q)

            IDLE: begin
                // Démarrer quand APB entre en phase ACCESS
                if (psel_i && penable_i)
                    state_d = pwrite_i ? WR_ACTIVE : RD_ACTIVE;
            end

            WR_ACTIVE: begin
                // Piloter AW et W simultanément, décocher au fur et à mesure
                awvalid_o = !aw_done_q;
                wvalid_o  = !w_done_q;
                // Passer à WR_RESP quand les deux canaux sont acquittés
                if ((aw_done_q || awready_i) && (w_done_q || wready_i))
                    state_d = WR_RESP;
            end

            WR_RESP: begin
                bready_o = 1'b1;
                if (bvalid_i) begin
                    pready_o  = 1'b1;
                    pslverr_o = (bresp_i != 2'b00);
                    state_d   = IDLE;
                end
            end

            RD_ACTIVE: begin
                arvalid_o = 1'b1;
                if (arready_i)
                    state_d = RD_DATA;
            end

            RD_DATA: begin
                rready_o = 1'b1;
                if (rvalid_i) begin
                    pready_o  = 1'b1;
                    pslverr_o = (rresp_i != 2'b00);
                    state_d   = IDLE;
                end
            end

            default: state_d = IDLE;
        endcase
    end

endmodule
