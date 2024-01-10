module librehome.nes.ppu;

import core.stdc.stdint;

__gshared  const ubyte[4][2] nametableMirrorLookup = [
    [0, 0, 1, 1], // Vertical
    [0, 1, 0, 1]  // Horizontal
];

/**
 * Default hardcoded palette.
 */
__gshared const uint32_t[64] defaultPaletteRGB = [
    0x7c7c7c,
    0x0000fc,
    0x0000bc,
    0x4428bc,
    0x940084,
    0xa80020,
    0xa81000,
    0x881400,
    0x503000,
    0x007800,
    0x006800,
    0x005800,
    0x004058,
    0x000000,
    0x000000,
    0x000000,
    0xbcbcbc,
    0x0078f8,
    0x0058f8,
    0x6844fc,
    0xd800cc,
    0xe40058,
    0xf83800,
    0xe45c10,
    0xac7c00,
    0x00b800,
    0x00a800,
    0x00a844,
    0x008888,
    0x000000,
    0x000000,
    0x000000,
    0xf8f8f8,
    0x3cbcfc,
    0x6888fc,
    0x9878f8,
    0xf878f8,
    0xf85898,
    0xf87858,
    0xfca044,
    0xf8b800,
    0xb8f818,
    0x58d854,
    0x58f898,
    0x00e8d8,
    0x787878,
    0x000000,
    0x000000,
    0xfcfcfc,
    0xa4e4fc,
    0xb8b8f8,
    0xd8b8f8,
    0xf8b8f8,
    0xf8a4c0,
    0xf0d0b0,
    0xfce0a8,
    0xf8d878,
    0xd8f878,
    0xb8f8b8,
    0xb8f8d8,
    0x00fcfc,
    0xf8d8f8,
    0x000000,
    0x000000
];

/**
 * RGB representation of the NES palette.
 */
__gshared const(uint32_t)* paletteRGB = defaultPaletteRGB.ptr;

/**
 * Emulates the NES Picture Processing Unit.
 */
struct PPU
{
    ubyte[] nesCPUVRAM;
    ubyte readRegister(ushort address)
    {
        static int cycle = 0;
        switch(address)
        {
        // PPUSTATUS
        case 0x2002:
            writeToggle = false;
            return (cycle++ % 2 == 0 ? 0xc0 : 0);
        // OAMDATA
        case 0x2004:
            return oam[oamAddress];
        // PPUDATA
        case 0x2007:
            return readDataRegister();
        default:
            break;
        }

        return 0;
    }

    /**
     * Render to a frame buffer.
     */
    void render(uint32_t* buffer)
    {
        // Clear the buffer with the background color
        for (int index = 0; index < 256 * 240; index++)
        {
            buffer[index] = paletteRGB[palette[0]];
        }

        // Draw sprites behind the backround
        if (ppuMask & (1 << 4)) // Are sprites enabled?
        {
            // Sprites with the lowest index in OAM take priority.
            // Therefore, render the array of sprites in reverse order.
            //
            for (int i = 63; i >= 0; i--)
            {
                // Read OAM for the sprite
                ubyte y          = oam[i * 4];
                ubyte index      = oam[i * 4 + 1];
                ubyte attributes = oam[i * 4 + 2];
                ubyte x          = oam[i * 4 + 3];

                // Check if the sprite has the correct priority
                if (!(attributes & (1 << 5)))
                {
                    continue;
                }

                // Check if the sprite is visible
                if( y >= 0xef || x >= 0xf9 )
                {
                    continue;
                }

                // Increment y by one since sprite data is delayed by one scanline
                //
                y++;

                // Determine the tile to use
                ushort tile = index + (ppuCtrl & (1 << 3) ? 256 : 0);
                bool flipX = (attributes & (1 << 6)) != 0;
                bool flipY = (attributes & (1 << 7)) != 0;

                // Copy pixels to the framebuffer
                for( int row = 0; row < 8; row++ )
                {
                    ubyte plane1 = readCHR(tile * 16 + row);
                    ubyte plane2 = readCHR(tile * 16 + row + 8);

                    for( int column = 0; column < 8; column++ )
                    {
                        ubyte paletteIndex = (((plane1 & (1 << column)) ? 1 : 0) + ((plane2 & (1 << column)) ? 2 : 0));
                        ubyte colorIndex = palette[0x10 + (attributes & 0x03) * 4 + paletteIndex];
                        if( paletteIndex == 0 )
                        {
                            // Skip transparent pixels
                            continue;
                        }
                        uint32_t pixel = 0xff000000 | paletteRGB[colorIndex];

                        int xOffset = 7 - column;
                        if( flipX )
                        {
                            xOffset = column;
                        }
                        int yOffset = row;
                        if( flipY )
                        {
                            yOffset = 7 - row;
                        }

                        int xPixel = cast(int)x + xOffset;
                        int yPixel = cast(int)y + yOffset;
                        if (xPixel < 0 || xPixel >= 256 || yPixel < 0 || yPixel >= 240)
                        {
                            continue;
                        }

                        buffer[yPixel * 256 + xPixel] = pixel;
                    }
                }
            }
        }

        // Draw the background (nametable)
        if (ppuMask & (1 << 3)) // Is the background enabled?
        {
            int scrollX = cast(int)ppuScrollX + ((ppuCtrl & (1 << 0)) ? 256 : 0);
            int xMin = scrollX / 8;
            int xMax = (cast(int)scrollX + 256) / 8;
            for (int x = 0; x < 32; x++)
            {
                for (int y = 0; y < 4; y++)
                {
                    // Render the status bar in the same position (it doesn't scroll)
                    renderTile(buffer, 0x2000 + 32 * y + x, x * 8, y * 8);
                }
            }
            for (int x = xMin; x <= xMax; x++)
            {
                for (int y = 4; y < 30; y++)
                {
                    // Determine the index of the tile to render
                    int index;
                    if (x < 32)
                    {
                        index = 0x2000 + 32 * y + x;
                    }
                    else if (x < 64)
                    {
                        index = 0x2400 + 32 * y + (x - 32);
                    }
                    else
                    {
                        index = 0x2800 + 32 * y + (x - 64);
                    }

                    // Render the tile
                    renderTile(buffer, index, (x * 8) - cast(int)scrollX, (y * 8));
                }
            }
        }

        // Draw sprites in front of the background
        if (ppuMask & (1 << 4))
        {
            // Sprites with the lowest index in OAM take priority.
            // Therefore, render the array of sprites in reverse order.
            //
            // We render sprite 0 first as a special case (coin indicator).
            //
            for (int j = 64; j > 0; j--)
            {
                // Start at 0, then 63, 62, 61, ..., 1
                //
                int i = j % 64;

                // Read OAM for the sprite
                ubyte y          = oam[i * 4];
                ubyte index      = oam[i * 4 + 1];
                ubyte attributes = oam[i * 4 + 2];
                ubyte x          = oam[i * 4 + 3];

                // Check if the sprite has the correct priority
                //
                if (attributes & (1 << 5) && !(i == 0 && index == 0xff))
                {
                    continue;
                }

                // Check if the sprite is visible
                if( y >= 0xef || x >= 0xf9 )
                {
                    continue;
                }

                // Increment y by one since sprite data is delayed by one scanline
                //
                y++;

                // Determine the tile to use
                ushort tile = index + (ppuCtrl & (1 << 3) ? 256 : 0);
                bool flipX = (attributes & (1 << 6)) != 0;
                bool flipY = (attributes & (1 << 7)) != 0;

                // Copy pixels to the framebuffer
                for( int row = 0; row < 8; row++ )
                {
                    ubyte plane1 = readCHR(tile * 16 + row);
                    ubyte plane2 = readCHR(tile * 16 + row + 8);

                    for( int column = 0; column < 8; column++ )
                    {
                        ubyte paletteIndex = (((plane1 & (1 << column)) ? 1 : 0) + ((plane2 & (1 << column)) ? 2 : 0));
                        ubyte colorIndex = palette[0x10 + (attributes & 0x03) * 4 + paletteIndex];
                        if( paletteIndex == 0 )
                        {
                            // Skip transparent pixels
                            continue;
                        }
                        uint32_t pixel = 0xff000000 | paletteRGB[colorIndex];

                        int xOffset = 7 - column;
                        if( flipX )
                        {
                            xOffset = column;
                        }
                        int yOffset = row;
                        if( flipY )
                        {
                            yOffset = 7 - row;
                        }

                        int xPixel = cast(int)x + xOffset;
                        int yPixel = cast(int)y + yOffset;
                        if (xPixel < 0 || xPixel >= 256 || yPixel < 0 || yPixel >= 240)
                        {
                            continue;
                        }

                        if (i == 0 && index == 0xff && row == 5 && column > 3 && column < 6)
                        {
                            continue;
                        }

                        buffer[yPixel * 256 + xPixel] = pixel;
                    }
                }
            }
        }
    }

    void writeRegister(ushort address, ubyte value)
    {
        switch(address)
        {
        // PPUCTRL
        case 0x2000:
            ppuCtrl = value;
            break;
        // PPUMASK
        case 0x2001:
            ppuMask = value;
            break;
        // OAMADDR
        case 0x2003:
            oamAddress = value;
            break;
        // OAMDATA
        case 0x2004:
            oam[oamAddress] = value;
            oamAddress++;
            break;
        // PPUSCROLL
        case 0x2005:
            if (!writeToggle)
            {
                ppuScrollX = value;
            }
            else
            {
                ppuScrollY = value;
            }
            writeToggle = !writeToggle;
            break;
        // PPUADDR
        case 0x2006:
            writeAddressRegister(value);
            break;
        // PPUDATA
        case 0x2007:
            writeDataRegister(value);
            break;
        default:
            break;
        }
    }

    private ubyte ppuCtrl; /**< $2000 */
    private ubyte ppuMask; /**< $2001 */
    private ubyte ppuStatus; /**< 2002 */
    private ubyte oamAddress; /**< $2003 */
    private ubyte ppuScrollX; /**< $2005 */
    private ubyte ppuScrollY; /**< $2005 */

    private ubyte[32] palette; /**< Palette data. */
    private ubyte[2048] nametable; /**< Background table. */
    private ubyte[256] oam; /**< Sprite memory. */

    // PPU Address control
    private ushort currentAddress; /**< Address that will be accessed on the next PPU read/write. */
    private bool writeToggle; /**< Toggles whether the low or high bit of the current address will be set on the next write to PPUADDR. */
    private ubyte vramBuffer; /**< Stores the last read byte from VRAM to delay reads by 1 byte. */

    private ubyte getAttributeTableValue(ushort nametableAddress)
    {
        nametableAddress = getNametableIndex(nametableAddress);

        // Determine the 32x32 attribute table address
        int row = ((nametableAddress & 0x3e0) >> 5) / 4;
        int col = (nametableAddress & 0x1f) / 4;

        // Determine the 16x16 metatile for the 8x8 tile addressed
        int shift = ((nametableAddress & (1 << 6)) ? 4 : 0) + ((nametableAddress & (1 << 1)) ? 2 : 0);

        // Determine the offset into the attribute table
        int offset = (nametableAddress & 0xc00) + 0x400 - 64 + (row * 8 + col);

        // Determine the attribute table value
        return (nametable[offset] & (0x3 << shift)) >> shift;
    }
    private ushort getNametableIndex(ushort address)
    {
        address = cast(ushort)((address - 0x2000) % 0x1000);
        int table = address / 0x400;
        int offset = address % 0x400;
        int mode = 1;
        return cast(ushort)((nametableMirrorLookup[mode][table] * 0x400 + offset) % 2048);
    }
    private ubyte readByte(ushort address)
    {
        // Mirror all addresses above $3fff
        address &= 0x3fff;

        if (address < 0x2000)
        {
            // CHR
            return nesCPUVRAM[address];
        }
        else if (address < 0x3f00)
        {
            // Nametable
            return nametable[getNametableIndex(address)];
        }

        return 0;
    }
    private ubyte readCHR(int index)
    {
        if (index < 0x2000)
        {
            return nesCPUVRAM[index];
        }
        else
        {
            return 0;
        }
    }
    private ubyte readDataRegister()
    {
        ubyte value = vramBuffer;
        vramBuffer = readByte(currentAddress);

        if (!(ppuCtrl & (1 << 2)))
        {
            currentAddress++;
        }
        else
        {
            currentAddress += 32;
        }

        return value;
    }
    private void renderTile(uint32_t* buffer, int index, int xOffset, int yOffset)
    {
        // Lookup the pattern table entry
        ushort tile = readByte(cast(ushort)index) + (ppuCtrl & (1 << 4) ? 256 : 0);
        ubyte attribute = getAttributeTableValue(cast(ushort)index);

        // Read the pixels of the tile
        for( int row = 0; row < 8; row++ )
        {
            ubyte plane1 = readCHR(tile * 16 + row);
            ubyte plane2 = readCHR(tile * 16 + row + 8);

            for( int column = 0; column < 8; column++ )
            {
                ubyte paletteIndex = (((plane1 & (1 << column)) ? 1 : 0) + ((plane2 & (1 << column)) ? 2 : 0));
                ubyte colorIndex = palette[attribute * 4 + paletteIndex];
                if( paletteIndex == 0 )
                {
                    // skip transparent pixels
                    //colorIndex = palette[0];
                    continue;
                }
                uint32_t pixel = 0xff000000 | paletteRGB[colorIndex];

                int x = (xOffset + (7 - column));
                int y = (yOffset + row);
                if (x < 0 || x >= 256 || y < 0 || y >= 240)
                {
                    continue;
                }
                buffer[y * 256 + x] = pixel;
            }
        }

    }
    private void writeAddressRegister(ubyte value)
    {
        if (!writeToggle)
        {
            // Upper byte
            currentAddress = (currentAddress & 0xff) | ((cast(ushort)value << 8) & 0xff00);
        }
        else
        {
            // Lower byte
            currentAddress = (currentAddress & 0xff00) | cast(ushort)value;
        }
        writeToggle = !writeToggle;
    }
    private void writeByte(ushort address, ubyte value)
    {
        // Mirror all addrsses above $3fff
        address &= 0x3fff;

        if (address < 0x2000)
        {
            // CHR (no-op)
        }
        else if (address < 0x3f00)
        {
            nametable[getNametableIndex(address)] = value;
        }
        else if (address < 0x3f20)
        {
            // Palette data
            palette[address - 0x3f00] = value;

            // Mirroring
            if (address == 0x3f10 || address == 0x3f14 || address == 0x3f18 || address == 0x3f1c)
            {
                palette[address - 0x3f10] = value;
            }
        }
    }
    private void writeDataRegister(ubyte value)
    {
        writeByte(currentAddress, value);
        if (!(ppuCtrl & (1 << 2)))
        {
            currentAddress++;
        }
        else
        {
            currentAddress += 32;
        }
    }
}
