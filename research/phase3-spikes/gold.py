# Gold labels for fixtures. A list entry may be a tuple of acceptable labels.
O,I,V,P,C,B,N,T='other','intro','verse','prechorus','chorus','bridge','instrumental','outro'
PASTE = {
 'E01-ug-headers': dict(labels=[O,I,V,C,V,C,B,T], title='Paper Lanterns', artist='The Hollow Pines', key='G', keyStated=False),
 'E02-bare-no-headers': dict(labels=[O,V,C,V,C], title='Gravel Road Home', artist=None, key='G', keyStated=False),
 'E03-inline-chordpro': dict(labels=[O,V,C,V,C], title='Saltwater Letters', artist='June & the Lighthouse', key='D', keyStated=False),
 'E04-tabs-mixed': dict(labels=[O,(I,N),V,C,N,V,C], title='Iron Kettle', artist='Westbrook Lane', key='Am', keyStated=False),
 'E05-colon-headers-repeats': dict(labels=[O,V,P,C,V,P,C], title='Summer in the Attic', artist=None, key='D', keyStated=True),
 'E06-crlf-smartquotes': dict(labels=[O,V,C,V,C], title='Lighthouse Keeper', artist='Arlo Fenn', key=('Em','G'), keyStated=False),
 'E07-short-unlabelled': dict(labels=[V,C], title=None, artist=None, key='A', keyStated=False),
 'E08-long': dict(labels=[O,I,V,V,P,C,V,P,C,N,B,V,C,C,T], title='Long Way Through Winter', artist='The Cedar Line', key='E', keyStated=True),
 'E09-web-junk': dict(labels=[O,V,C,V,C,O], title='Glass Houses', artist='Penny Marlowe', key=('Dm','F'), keyStated=False),
 'E10-edgy-lyrics': dict(labels=[O,V,C,V,C], title='Whiskey and Gunpowder', artist='Red Mesa Drifters', key='A', keyStated=False),
 'E11-abbrev-headers': dict(labels=[(O,I),V,C,V,C,B,C], title='Neon Saints', artist='Tess Calder', key='C', keyStated=False),
 'E12-bare-lyrics': dict(labels=[O,V,C,V,C,B,C], title='Northbound', artist='Mara Quinn', key='unknown', keyStated=False),
 'H01-ug-hinglish': dict(labels=[O,I,V,C,V,C,T], title='Dil Ki Baatein', artist='Raahi Band', key='Am', keyStated=False),
 'H02-bare-hinglish': dict(labels=[O,V,C,V,C], title='Barish Wali Shaam', artist=None, key='G', keyStated=False),
 'H03-mukhda-antara-inline': dict(labels=[O,C,V,C,V,C], title='Safar', artist='Kabir Sehgal', key='D', keyStated=False),
 'H04-long-hinglish': dict(labels=[O,I,V,V,P,C,V,P,C,N,B,V,C,C,T], title='Jugnu', artist='Mehfil Collective', key='Em', keyStated=True),
 'H05-indian-site-junk': dict(labels=[O,V,C,V,C,O], title='Pehli Mohabbat', artist='Ananya Rao', key='C', keyStated=False),
 'H06-scale-capo-tab': dict(labels=[O,(I,N),V,C,V,C], title='Mitti Ki Khushboo', artist='Zoya & The Village Band', key='Am', keyStated=True),
 'H07-bare-hinglish-lyrics': dict(labels=[V,C,V,C], title=None, artist=None, key='unknown', keyStated=False),
 'H08-codemixed': dict(labels=[O,V,C,V,C], title='Late Night Dilli', artist=('DJ Saahil ft. Rhea','DJ Saahil'), key='Em', keyStated=False),
}
# Set-request gold: field -> acceptable values (tuple). Unlisted fields must be default.
DEFAULTS = dict(targetMinutes=None, songCount=None, minProficiency='any', energyMin=None, energyMax=None,
    openerEnergy='any', closer='any', includeTags=[], excludeTags=[], keys=[], tempoMinBPM=None, tempoMaxBPM=None)
SET = {
 'S1': dict(targetMinutes=45, minProficiency='ready', openerEnergy='high'),
 'S2': dict(includeTags=[['upbeat']], keys=[['G']], minProficiency='ready', songCount=(None,1)),
 'S3': dict(targetMinutes=60, includeTags=[['acoustic']], minProficiency='ready'),
 'S4': dict(songCount=10, includeTags=[['wedding']], closer='crowd pleaser'),
 'S5': dict(targetMinutes=30, includeTags=[['hindi']], minProficiency='pro'),
 'S6': dict(includeTags=[['ballad']], tempoMaxBPM=90, energyMax=(None,2)),
 'S7': dict(targetMinutes=90, includeTags=[['rock']], excludeTags=[['cover']], energyMin=4),
 'S8': dict(targetMinutes=20, openerEnergy='low'),
 'S9': dict(targetMinutes=120, includeTags=[['original']], keys=[['D','A']]),
 'S10': dict(includeTags=[['singalong']], tempoMinBPM=100, tempoMaxBPM=130),
 'S11': dict(songCount=5, keys=[['Em']], energyMax=2),
 'S12': dict(targetMinutes=40, excludeTags=[['hindi']], closer=('high','crowd pleaser')),
 'S13': dict(targetMinutes=90, energyMax=2, minProficiency=('any','ready')),
 'S14': dict(targetMinutes=25, includeTags=[['hindi'],['hindi','ballad']]),
 'S15': dict(targetMinutes=75, includeTags=[['crowd pleaser','singalong']], minProficiency='ready'),
}
