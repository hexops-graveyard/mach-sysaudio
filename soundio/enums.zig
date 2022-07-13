const c = @import("c.zig");

pub const ChannelId = enum(u7) {
    invalid = c.SoundIoChannelIdInvalid,

    front_left = c.SoundIoChannelIdFrontLeft,
    front_right = c.SoundIoChannelIdFrontRight,
    front_center = c.SoundIoChannelIdFrontCenter,
    lfe = c.SoundIoChannelIdLfe,
    back_left = c.SoundIoChannelIdBackLeft,
    back_right = c.SoundIoChannelIdBackRight,
    front_left_center = c.SoundIoChannelIdFrontLeftCenter,
    front_right_center = c.SoundIoChannelIdFrontRightCenter,
    back_center = c.SoundIoChannelIdBackCenter,
    side_left = c.SoundIoChannelIdSideLeft,
    side_right = c.SoundIoChannelIdSideRight,
    top_center = c.SoundIoChannelIdTopCenter,
    top_front_left = c.SoundIoChannelIdTopFrontLeft,
    top_front_center = c.SoundIoChannelIdTopFrontCenter,
    top_front_right = c.SoundIoChannelIdTopFrontRight,
    top_back_left = c.SoundIoChannelIdTopBackLeft,
    top_back_center = c.SoundIoChannelIdTopBackCenter,
    top_back_right = c.SoundIoChannelIdTopBackRight,

    back_left_center = c.SoundIoChannelIdBackLeftCenter,
    back_right_center = c.SoundIoChannelIdBackRightCenter,
    front_left_wide = c.SoundIoChannelIdFrontLeftWide,
    front_right_wide = c.SoundIoChannelIdFrontRightWide,
    front_left_high = c.SoundIoChannelIdFrontLeftHigh,
    front_center_high = c.SoundIoChannelIdFrontCenterHigh,
    front_right_high = c.SoundIoChannelIdFrontRightHigh,
    top_front_left_center = c.SoundIoChannelIdTopFrontLeftCenter,
    top_front_right_center = c.SoundIoChannelIdTopFrontRightCenter,
    top_side_left = c.SoundIoChannelIdTopSideLeft,
    top_side_right = c.SoundIoChannelIdTopSideRight,
    left_lfe = c.SoundIoChannelIdLeftLfe,
    right_lfe = c.SoundIoChannelIdRightLfe,
    lfe2 = c.SoundIoChannelIdLfe2,
    bottom_center = c.SoundIoChannelIdBottomCenter,
    bottom_left_center = c.SoundIoChannelIdBottomLeftCenter,
    bottom_right_center = c.SoundIoChannelIdBottomRightCenter,

    // Mid/side recording
    ms_mid = c.SoundIoChannelIdMsMid,
    ms_side = c.SoundIoChannelIdMsSide,

    // first order ambisonic channels
    ambisonic_w = c.SoundIoChannelIdAmbisonicW,
    ambisonic_x = c.SoundIoChannelIdAmbisonicX,
    ambisonic_y = c.SoundIoChannelIdAmbisonicY,
    ambisonic_z = c.SoundIoChannelIdAmbisonicZ,

    // X-Y Recording
    x_y_x = c.SoundIoChannelIdXyX,
    x_y_y = c.SoundIoChannelIdXyY,

    headphones_left = c.SoundIoChannelIdHeadphonesLeft,
    headphones_right = c.SoundIoChannelIdHeadphonesRight,
    click_track = c.SoundIoChannelIdClickTrack,
    foreign_language = c.SoundIoChannelIdForeignLanguage,
    hearing_impaired = c.SoundIoChannelIdHearingImpaired,
    narration = c.SoundIoChannelIdNarration,
    haptic = c.SoundIoChannelIdHaptic,
    dialog_centric_mix = c.SoundIoChannelIdDialogCentricMix,

    aux = c.SoundIoChannelIdAux,
    aux0 = c.SoundIoChannelIdAux0,
    aux1 = c.SoundIoChannelIdAux1,
    aux2 = c.SoundIoChannelIdAux2,
    aux3 = c.SoundIoChannelIdAux3,
    aux4 = c.SoundIoChannelIdAux4,
    aux5 = c.SoundIoChannelIdAux5,
    aux6 = c.SoundIoChannelIdAux6,
    aux7 = c.SoundIoChannelIdAux7,
    aux8 = c.SoundIoChannelIdAux8,
    aux9 = c.SoundIoChannelIdAux9,
    aux10 = c.SoundIoChannelIdAux10,
    aux11 = c.SoundIoChannelIdAux11,
    aux12 = c.SoundIoChannelIdAux12,
    aux13 = c.SoundIoChannelIdAux13,
    aux14 = c.SoundIoChannelIdAux14,
    aux15 = c.SoundIoChannelIdAux15,
};

pub const ChannelLayoutId = enum(u5) {
    mono = c.SoundIoChannelLayoutIdMono,
    stereo = c.SoundIoChannelLayoutIdStereo,
    _2point1 = c.SoundIoChannelLayoutId2Point1,
    _3point0 = c.SoundIoChannelLayoutId3Point0,
    _3point0_back = c.SoundIoChannelLayoutId3Point0Back,
    _3point1 = c.SoundIoChannelLayoutId3Point1,
    _4point0 = c.SoundIoChannelLayoutId4Point0,
    quad = c.SoundIoChannelLayoutIdQuad,
    quadSide = c.SoundIoChannelLayoutIdQuadSide,
    _4point1 = c.SoundIoChannelLayoutId4Point1,
    _5point0_back = c.SoundIoChannelLayoutId5Point0Back,
    _5point0_side = c.SoundIoChannelLayoutId5Point0Side,
    _5point1 = c.SoundIoChannelLayoutId5Point1,
    _5point1_back = c.SoundIoChannelLayoutId5Point1Back,
    _6point0_side = c.SoundIoChannelLayoutId6Point0Side,
    _6point0_front = c.SoundIoChannelLayoutId6Point0Front,
    hexagonal = c.SoundIoChannelLayoutIdHexagonal,
    _6point1 = c.SoundIoChannelLayoutId6Point1,
    _6point1_back = c.SoundIoChannelLayoutId6Point1Back,
    _6point1_front = c.SoundIoChannelLayoutId6Point1Front,
    _7point0 = c.SoundIoChannelLayoutId7Point0,
    _7point0_front = c.SoundIoChannelLayoutId7Point0Front,
    _7point1 = c.SoundIoChannelLayoutId7Point1,
    _7point1_wide = c.SoundIoChannelLayoutId7Point1Wide,
    _7point1_wide_back = c.SoundIoChannelLayoutId7Point1WideBack,
    octagonal = c.SoundIoChannelLayoutIdOctagonal,
};

pub const Backend = enum(u3) {
    none = c.SoundIoBackendNone,
    jack = c.SoundIoBackendJack,
    pulseaudio = c.SoundIoBackendPulseAudio,
    alsa = c.SoundIoBackendAlsa,
    coreaudio = c.SoundIoBackendCoreAudio,
    wasapi = c.SoundIoBackendWasapi,
    dummy = c.SoundIoBackendDummy,
};

pub const Aim = enum(u1) {
    input = c.SoundIoDeviceAimInput,
    output = c.SoundIoDeviceAimOutput,
};

pub const Format = enum(u5) {
    invalid = c.SoundIoFormatInvalid,
    S8 = c.SoundIoFormatS8,
    U8 = c.SoundIoFormatU8,
    S16LE = c.SoundIoFormatS16LE,
    S16BE = c.SoundIoFormatS16BE,
    U16LE = c.SoundIoFormatU16LE,
    U16BE = c.SoundIoFormatU16BE,
    S24LE = c.SoundIoFormatS24LE,
    S24BE = c.SoundIoFormatS24BE,
    U24LE = c.SoundIoFormatU24LE,
    U24BE = c.SoundIoFormatU24BE,
    S32LE = c.SoundIoFormatS32LE,
    S32BE = c.SoundIoFormatS32BE,
    U32LE = c.SoundIoFormatU32LE,
    U32BE = c.SoundIoFormatU32BE,
    float32LE = c.SoundIoFormatFloat32LE,
    float32BE = c.SoundIoFormatFloat32BE,
    float64LE = c.SoundIoFormatFloat64LE,
    float64BE = c.SoundIoFormatFloat64BE,
};
