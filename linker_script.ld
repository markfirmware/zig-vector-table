MEMORY {
    flash : ORIGIN = 0x0, LENGTH = 0x40000
    ram : ORIGIN = 0x20000000, LENGTH = 0x4000
}
SECTIONS {
    .flash : {
        _start = .;
        KEEP(*(.vector_table))
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        _ram_data_initial_values = .;
    } > flash
    .ram_data : AT(_ram_data_initial_values) {
        _ram_data_start = .;
        *(.data)
        _ram_data_end = .;
    } > ram
    .ram_bss (NOLOAD) : {
        _ram_bss_start = .;
        *(.bss)
        _ram_bss_end = .;
    } > ram
    # .ARM.exidx must be discarded until "Provide -fno-unwind-tables" is resolved https://github.com/ziglang/zig/issues/5464
    /DISCARD/ : {
        *(.ARM.exidx)
    }
}
