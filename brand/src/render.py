import sys, asyncio
from playwright.async_api import async_playwright
async def shots(jobs):
    async with async_playwright() as p:
        b=await p.chromium.launch()
        pg=await b.new_page()
        for html,w,h,out,transparent in jobs:
            await pg.set_viewport_size({"width":w,"height":h})
            await pg.set_content(f'<html><body style="margin:0;background:transparent">{html}</body></html>')
            await pg.screenshot(path=out, omit_background=transparent, clip={"x":0,"y":0,"width":w,"height":h})
        await b.close()
def render(jobs): asyncio.run(shots(jobs))
