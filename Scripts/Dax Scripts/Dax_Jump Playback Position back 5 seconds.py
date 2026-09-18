# @description Jump Playback Position back 5 seconds
# @version 1.0
# @author Dax Liniere

#version 1.0
from reaper_python import *

def DoTheJump():
	currentPlayPosition=RPR_GetPlayPosition()

	newPlayPosition=currentPlayPosition-5 #in seconds
	RPR_SetEditCurPos(newPlayPosition, True, True)
	
#junk results happen if the playback isn't on...0 is "stopped"
if RPR_GetPlayState()!=0:
	DoTheJump()
