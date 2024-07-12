MEMORY {
    flash : ORIGIN = 0x0, LENGTH = 0x40000
    ram : ORIGIN = 0x20000000, LENGTH = 0x4000
}
SECTIONS {
    /DISCARD/ : {
        *(.ARM.exidx)
    }
    .flash : {
        _start = .;
        KEEP(*(.vector_table))
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        _address_in_flash_of_initial_ram_data = .;
    } > flash
    .ram_data : AT(_address_in_flash_of_initial_ram_data) {
        _ram_data_start = .;
        *(.data)
        _ram_data_end = .;
    } > ram
    .ram_bss (NOLOAD) : {
        _ram_bss_start = .;
        *(.bss)
        _ram_bss_end = .;
    } > ram
}
