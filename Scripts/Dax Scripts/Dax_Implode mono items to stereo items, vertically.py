# @description Implode mono items to stereo items, vertically
# @version 1.0
# @author Dax Liniere

### Python: Make stereo items from mono items, vertically ###
from reaper_python import *
from contextlib import contextmanager

@contextmanager
def undoable(message):
    RPR_Undo_BeginBlock2(0)
    try:
        yield
    finally:
        RPR_Undo_EndBlock2(0, message, -1)

@contextmanager
def noUIRefresh():
    RPR_PreventUIRefresh(1)
    try:
        yield
    finally:
        RPR_PreventUIRefresh(-1)        

def FnL2():
    cmi = RPR_CountMediaItems(0)
    for c in range(cmi):
        CurrItem = RPR_GetMediaItem(0, c)
        if RPR_IsMediaItemSelected(CurrItem):
            smiL.append(CurrItem)
            pos = round(RPR_GetMediaItemInfo_Value(CurrItem, "D_POSITION"), 10)
            length = round(RPR_GetMediaItemInfo_Value(CurrItem, "D_LENGTH"), 10)
            plL = [pos, length]
            if plL in timeL:
                itemL[timeL.index(plL)].append(c)
            else:
                timeL.append(plL)
                itemL.append([c])

def FnImplodeToStereo():
    for i in range(len(itemL)):
        LL = len(itemL[i])
        if LL > 1:
            RPR_Main_OnCommand(40289, 0)#unselect all items
            for g in range(LL):
                implodeItem = RPR_GetMediaItem(0, int(itemL[i][g]))
                RPR_SetMediaItemSelected(implodeItem, 1)
            RPR_Main_OnCommand(RPR_NamedCommandLookup("_XENAKIOS_IMPLODEITEMSPANSYMMETRICALLY"), 0)#implode items to stereo

def FnReselect():
    for s in range(len(smiL)):
        RPR_SetMediaItemSelected(smiL[s], 1)

with undoable("Make stereo items from mono items, vertically"):
    with noUIRefresh():
        smiL = []
        timeL = []
        itemL = []
        FnL2()
        FnImplodeToStereo()
        FnReselect()
        RPR_UpdateArrange()
