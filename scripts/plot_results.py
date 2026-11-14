from pathlib import Path
import csv
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
ROOT=Path(__file__).resolve().parents[1]
rows=list(csv.DictReader((ROOT/'data'/'vehicle_category_summary.csv').open(encoding='utf-8')))
labels=[r['car_body_type'].title() for r in rows]
colors=['#2563eb','#0d9488','#d97706']
plt.rcParams.update({'font.size':11,'axes.spines.top':False,'axes.spines.right':False})
fig,ax=plt.subplots(figsize=(9,5))
bars=ax.bar(labels,[int(r['booking_records']) for r in rows],color=colors)
ax.bar_label(bars,padding=4); ax.set_ylim(0,3900)
ax.set_ylabel('Booking records'); ax.set_title('Vehicle-category booking demand')
fig.tight_layout(); fig.savefig(ROOT/'assets'/'bookings.png',dpi=180); plt.close(fig)
fig,axes=plt.subplots(1,2,figsize=(12,4.8))
for ax,key,title,unit in [(axes[0],'bookings_per_vehicle','Fleet utilisation','Bookings per vehicle'),(axes[1],'maintenance_cost_per_booking','Maintenance cost burden','Cost units per booking')]:
    bars=ax.bar(labels,[float(r[key]) for r in rows],color=colors)
    ax.bar_label(bars,fmt='%.2f',padding=4)
    ax.set_ylim(0,max(float(r[key]) for r in rows)*1.18)
    ax.set_title(title); ax.set_ylabel(unit)
fig.tight_layout();fig.savefig(ROOT/'assets'/'utilisation-and-cost.png',dpi=180);plt.close(fig)
fig,ax=plt.subplots(figsize=(9,5)); x=list(range(len(rows))); w=.36
a=ax.bar([v-w/2 for v in x],[int(r['accident_records_involving_body']) for r in rows],w,label='Accident involvements',color='#2563eb')
b=ax.bar([v+w/2 for v in x],[int(r['severe_accident_records']) for r in rows],w,label='Severe involvements',color='#d97706')
ax.bar_label(a,padding=3);ax.bar_label(b,padding=3);ax.set_xticks(x,labels)
ax.set_ylabel('Records');ax.set_ylim(0,450);ax.set_title('Accident involvement and severity')
ax.legend(frameon=False);fig.tight_layout();fig.savefig(ROOT/'assets'/'accident-profile.png',dpi=180)
