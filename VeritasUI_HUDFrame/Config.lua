-- VeritasUI_HUDFrame / Config.lua
-- Named constants for all frame dimensions, screen positions, and warning thresholds.
-- Tune here without touching HUDFrame.lua.

local _, HUF = ...

HUF.Config = {
    -- Chat anchor frame dimensions (container including border)
    CHAT_FRAME_W    = 380,
    CHAT_FRAME_H    = 200,

    -- Screen-edge offsets for the chat anchors.
    -- CHAT_LEFT_X  : pixels from the left edge of the screen.
    -- CHAT_RIGHT_X : pixels from the right edge of the screen (applied as negative offset).
    CHAT_LEFT_X     = 0,
    CHAT_RIGHT_X    = 0,

    -- Bottom edge of the chat anchor frames, in pixels from the screen bottom.
    -- The left and right data bars sit flush below this line.
    CHAT_BOTTOM_Y   = 200,

    -- How many pixels the DialogBox border extends into the frame on each side.
    -- The docked chat frame is inset by this amount on all four sides.
    BORDER_INSET    = 11,

    -- Height of each data text bar (pixels)
    BAR_HEIGHT      = 22,

    -- Center bar: total width and position of its bottom edge above the screen bottom.
    -- Raise CENTER_BAR_Y if your action bar cluster is taller than the default layout.
    CENTER_BAR_W    = 500,
    CENTER_BAR_Y    = 190,

    -- Seconds between full bar refreshes
    TICKER_INTERVAL = 2,

    -- Data warning thresholds
    WARN_DURABILITY_PCT = 20,   -- durability below this % → red
    WARN_MEMORY_MB      = 80,   -- memory above this MB  → red

    -- Default frame dimensions used by the Frame Sizes slider system
    leftAnchorWidth  = 380,
    leftAnchorHeight = 220,
    rightAnchorWidth = 380,
    rightAnchorHeight = 220,
    centerBarWidth   = 500,
}
