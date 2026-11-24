import datetime, json, pathlib, sys, uuid
now = datetime.datetime.now(datetime.timezone.utc)
reference = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
t = (now-reference).total_seconds()
sessions = []
for n in range(3):
    end = t-(n+1)*86400
    sessions.append(dict(id=str(uuid.uuid4()), started=end-10800, ends=end, minutes=180, plantID="cherry", strict=False, isBreak=False, status="done"))
redemptions = [dict(id=str(uuid.uuid4()), rewardID=id, title=name, cost=cost, date=t) for id,name,cost in [("cherry","Anh đào",180),("sunset","Hoàng hôn",160),("butterfly","Bướm ghé thăm",100)]]
state = dict(version=1, habits=[], checkIns=[], chests=[], redemptions=redemptions, customRewards=[], equipped="original", petName="Mầm", reminderEnabled=False, reminderHour=20, reminderMinute=0,
    focus=dict(growthRevision=3, selectedPlant="cherry", growth={"cherry":dict(water=0,sunlight=0,points=1080)}, sessions=sessions, decorations={"Nền":"sunset","Trang trí":"butterfly"}))
path=pathlib.Path(sys.argv[1]);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(state,ensure_ascii=False))
