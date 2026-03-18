// ============================================================
//  accel_wrap.sv — Template d'accélérateur DMA autonome
//  À dupliquer pour chaque accélérateur (accel1_wrap, accel2_wrap)
//
//  Topologie interne :
//
//    XBAR ─MMIO──► axi_cfg (slave)
//                     │
//                     ▼
//              ┌──────────────────────────────┐
//              │  accel_wrap                  │
//              │                              │
//              │  ┌──────────────────────┐    │
//              │  │  logique de calcul   │    │
//              │  │  (compute_core)      │    │
//              │  │                      │    │
//              │  │  dma_start_o ──────►─┤    │
//              │  │  dma_done_i  ◄─────── ┤   │
//              │  │  dma_src_addr_o ───►─ ┤   │
//              │  │  dma_dst_addr_o ───►─ ┤   │
//              │  │  dma_len_o     ───►─  ┤   │
//              │  └──────────────────────┘    │
//              │                              │
//              │  ┌──────────────────────┐    │
//              │  │  dma_core_wrap       │    │
//              │  │  (moteur DMA)        ├───►│ axi_dma (master MMU)
//              │  └──────────────────────┘    │
//              └──────────────────────────────┘
//
//  Paramètre STREAM_ID : valeur unique par accélérateur,
//  correspond à l'entrée DDT dans l'IOMMU.
//  Accel 1 → STREAM_ID = 1
//  Accel 2 → STREAM_ID = 2
// ============================================================

`include "axi/assign.svh"
`include "axi/typedef.svh"

module accel_wrap #(
    parameter int unsigned AXI_ADDR_WIDTH = 64,
    parameter int unsigned AXI_DATA_WIDTH = 64,
    parameter int unsigned AXI_ID_WIDTH   = 3,    // IdWidth-1 = 3b (mux ajoute 1 bit)
    parameter int unsigned AXI_USER_WIDTH = 1,
    parameter int unsigned AXI_SLV_ID_WIDTH = 6,  // IdWidthSlave
    // Identifiant IOMMU de ce device (unique par accélérateur)
    parameter logic [23:0] STREAM_ID      = 24'd1
) (
    input  logic clk_i,
    input  logic rst_ni,
    input  logic testmode_i,

    // Interface de configuration MMIO (esclave AXI, depuis le XBAR)
    AXI_BUS.Slave  axi_cfg,

    // Interface DMA maître (vers axi_mux → IOMMU TR IF)
    AXI_BUS_MMU.Master axi_dma
);

    // ----------------------------------------------------------
    //  Signaux de contrôle entre compute_core et dma_core_wrap
    // ----------------------------------------------------------
    logic        dma_start;       // compute → DMA : lancer un transfert
    logic        dma_done;        // DMA → compute : transfert terminé
    logic [63:0] dma_src_addr;    // adresse source  (espace virtuel device)
    logic [63:0] dma_dst_addr;    // adresse destination
    logic [31:0] dma_len;         // longueur en octets

    // ----------------------------------------------------------
    //  Bus interne DMA engine → port MMU du wrapper
    //  (dma_core_wrap pilote ce bus ; on y câble stream_id ensuite)
    // ----------------------------------------------------------
    AXI_BUS_MMU #(
        .AXI_ADDR_WIDTH ( AXI_ADDR_WIDTH ),
        .AXI_DATA_WIDTH ( AXI_DATA_WIDTH ),
        .AXI_ID_WIDTH   ( AXI_ID_WIDTH   ),
        .AXI_USER_WIDTH ( AXI_USER_WIDTH )
    ) idma_master ();

    // ----------------------------------------------------------
    //  DMA engine — même module que dans le projet existant
    //  Le compute_core le pilote via son interface de contrôle
    //  (ici simplifiée ; adapter à l'interface réelle de
    //   dma_core_wrap si elle diffère)
    // ----------------------------------------------------------
    dma_core_wrap #(
        .AXI_ADDR_WIDTH   ( AXI_ADDR_WIDTH   ),
        .AXI_DATA_WIDTH   ( AXI_DATA_WIDTH   ),
        .AXI_ID_WIDTH     ( AXI_ID_WIDTH     ),
        .AXI_USER_WIDTH   ( AXI_USER_WIDTH   ),
        .AXI_SLV_ID_WIDTH ( AXI_SLV_ID_WIDTH ),
        .AR_DEVICE_ID     ( STREAM_ID        ),
        .AW_DEVICE_ID     ( STREAM_ID        )
    ) i_dma (
        .clk_i      ( clk_i      ),
        .rst_ni     ( rst_ni     ),
        .testmode_i ( testmode_i ),
        // Configuration MMIO depuis le XBAR (dma_cfg ou dma_cfg2)
        .axi_slave  ( axi_cfg    ),
        // Master DMA interne (avant estampillage stream_id)
        .axi_master ( idma_master )
        // NOTE : si dma_core_wrap expose une interface de
        // déclenchement logicielle (start/done/addr), connecter ici.
        // Dans l'implémentation actuelle, le CVA6 programme directement
        // les registres via axi_cfg — voir compute_core ci-dessous.
    );

    // ----------------------------------------------------------
    //  Estampillage des champs IOMMU sur chaque transaction DMA
    //  Ces trois signaux sont les seuls ajouts vs AXI standard.
    // ----------------------------------------------------------

    // Canal AW — forwarding complet + stream_id
    assign axi_dma.aw_valid      = idma_master.aw_valid;
    assign idma_master.aw_ready  = axi_dma.aw_ready;
    assign axi_dma.aw_id         = idma_master.aw_id;
    assign axi_dma.aw_addr       = idma_master.aw_addr;
    assign axi_dma.aw_len        = idma_master.aw_len;
    assign axi_dma.aw_size       = idma_master.aw_size;
    assign axi_dma.aw_burst      = idma_master.aw_burst;
    assign axi_dma.aw_lock       = idma_master.aw_lock;
    assign axi_dma.aw_cache      = idma_master.aw_cache;
    assign axi_dma.aw_prot       = idma_master.aw_prot;
    assign axi_dma.aw_qos        = idma_master.aw_qos;
    assign axi_dma.aw_region     = idma_master.aw_region;
    assign axi_dma.aw_atop       = idma_master.aw_atop;
    assign axi_dma.aw_user       = idma_master.aw_user;
    // Champs IOMMU — identifient ce device dans la DDT
    assign axi_dma.aw_stream_id    = STREAM_ID;
    assign axi_dma.aw_ss_id_valid  = 1'b0;   // pas de substream ici
    assign axi_dma.aw_substream_id = 20'd0;

    // Canal W
    assign axi_dma.w_valid       = idma_master.w_valid;
    assign idma_master.w_ready   = axi_dma.w_ready;
    assign axi_dma.w_data        = idma_master.w_data;
    assign axi_dma.w_strb        = idma_master.w_strb;
    assign axi_dma.w_last        = idma_master.w_last;
    assign axi_dma.w_user        = idma_master.w_user;

    // Canal B
    assign idma_master.b_valid   = axi_dma.b_valid;
    assign axi_dma.b_ready       = idma_master.b_ready;
    assign idma_master.b_id      = axi_dma.b_id;
    assign idma_master.b_resp    = axi_dma.b_resp;
    assign idma_master.b_user    = axi_dma.b_user;

    // Canal AR — forwarding complet + stream_id
    assign axi_dma.ar_valid      = idma_master.ar_valid;
    assign idma_master.ar_ready  = axi_dma.ar_ready;
    assign axi_dma.ar_id         = idma_master.ar_id;
    assign axi_dma.ar_addr       = idma_master.ar_addr;
    assign axi_dma.ar_len        = idma_master.ar_len;
    assign axi_dma.ar_size       = idma_master.ar_size;
    assign axi_dma.ar_burst      = idma_master.ar_burst;
    assign axi_dma.ar_lock       = idma_master.ar_lock;
    assign axi_dma.ar_cache      = idma_master.ar_cache;
    assign axi_dma.ar_prot       = idma_master.ar_prot;
    assign axi_dma.ar_qos        = idma_master.ar_qos;
    assign axi_dma.ar_region     = idma_master.ar_region;
    assign axi_dma.ar_user       = idma_master.ar_user;
    // Champs IOMMU
    assign axi_dma.ar_stream_id    = STREAM_ID;
    assign axi_dma.ar_ss_id_valid  = 1'b0;
    assign axi_dma.ar_substream_id = 20'd0;

    // Canal R
    assign idma_master.r_valid   = axi_dma.r_valid;
    assign axi_dma.r_ready       = idma_master.r_ready;
    assign idma_master.r_id      = axi_dma.r_id;
    assign idma_master.r_data    = axi_dma.r_data;
    assign idma_master.r_resp    = axi_dma.r_resp;
    assign idma_master.r_last    = axi_dma.r_last;
    assign idma_master.r_user    = axi_dma.r_user;

    // ----------------------------------------------------------
    //  compute_core — logique de calcul de l'accélérateur
    //
    //  À REMPLACER par ton IP réelle (HLS, RTL custom, etc.)
    //
    //  Interface minimale suggérée :
    //    - Le CVA6 configure l'accélérateur via axi_cfg
    //      (registres start/status/src/dst/len mappés en MMIO)
    //    - L'accélérateur déclenche le DMA de façon autonome
    //      en écrivant lui-même dans les registres de dma_core_wrap
    //      (ou via une interface interne si tu modifies dma_core_wrap)
    //
    //  Exemple squelette :
    // ----------------------------------------------------------

    // (vide dans ce template — à instancier selon ton IP)
    //
    // compute_core #(
    //     .DATA_WIDTH ( AXI_DATA_WIDTH )
    // ) i_compute (
    //     .clk_i         ( clk_i        ),
    //     .rst_ni        ( rst_ni       ),
    //     // Signaux vers le DMA engine
    //     .dma_start_o   ( dma_start    ),
    //     .dma_done_i    ( dma_done     ),
    //     .dma_src_addr_o( dma_src_addr ),
    //     .dma_dst_addr_o( dma_dst_addr ),
    //     .dma_len_o     ( dma_len      )
    // );

    // Éviter les warnings sur les signaux non utilisés dans le template
    assign dma_start    = 1'b0;
    assign dma_src_addr = '0;
    assign dma_dst_addr = '0;
    assign dma_len      = '0;
    assign dma_done     = 1'b0;

endmodule