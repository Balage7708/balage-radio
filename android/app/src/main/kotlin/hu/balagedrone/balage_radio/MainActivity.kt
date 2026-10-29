package hu.balagedrone.balage_radio

import com.ryanheise.audioservice.AudioServiceActivity

// Az audio_service miatt (háttérlejátszás, értesítés, zárolt képernyő) ebből kell származnia.
class MainActivity : AudioServiceActivity()
