"""Offline identity regressions: python3 -m unittest discover -s tests -v."""
import ast
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import tempfile
import unicodedata
import unittest
from unittest.mock import patch
import urllib.parse

ASSETS=Path(__file__).resolve().parents[1]/'config/quickshell/assets'

def definitions(file,names,scope):
    tree=ast.parse((ASSETS/file).read_text())
    exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in names],type_ignores=[]),file,'exec'),scope)
    return scope

class MediaIdentity(unittest.TestCase):
    def picker(self,artist='Test Artist',title='My Song',duration=60):
        return definitions('lyrics.py',('identity','clean_artist','clean_title','pick'),{'re':re,'unicodedata':unicodedata,'a':artist,'t':title,'duration':duration})['pick']

    def item(self,**extra):
        return dict(trackName='My Song',artistName='Test Artist',duration=60,syncedLyrics='[00:01]hello',**extra)

    def test_wrong_title_or_artist_with_identical_duration_is_rejected(self):
        for field,value in (('trackName','Unrelated'),('artistName','Someone Else')):
            item=self.item();item[field]=value
            self.assertIsNone(self.picker()([item]))
        self.assertIsNone(self.picker(artist='')([self.item()]))

    def test_normalization_and_duration_tolerance(self):
        item=self.item();item.update(trackName='MY SONG (Official Video)',artistName='Test Artist - Topic',duration=65)
        self.assertIs(self.picker()([item]),item)
        item['duration']=80;self.assertIsNone(self.picker()([item]))
        item['duration']=60;self.assertIs(self.picker(title='My Ｓong')([item]),item)

    def test_only_supported_youtube_urls_supply_an_id(self):
        parser=definitions('subs.py',('youtube_id',),{'urllib':__import__('urllib'),'re':re})['youtube_id']
        for url in ('https://www.youtube.com/watch?v=abcdefghijk&t=10','https://youtu.be/abcdefghijk','https://music.youtube.com/watch?v=abcdefghijk','https://youtube.com/shorts/abcdefghijk','https://m.youtube.com/live/abcdefghijk'):
            self.assertEqual(parser(url),'abcdefghijk')
        for url in ('','file:///tmp/video','https://youtube.com.evil.test/watch?v=abcdefghijk','https://evil.test/?v=abcdefghijk','https://youtube.com/watch?v=bad','https://youtube.com/watch?v=abcdefghijk/other'):
            self.assertIsNone(parser(url))

    def test_no_url_never_searches_by_title(self):
        output=io.StringIO()
        with patch.object(sys,'argv',['subs.py','key','Ambiguous title','Channel','60']),patch('subprocess.run',side_effect=AssertionError('must not search')),redirect_stdout(output):
            with self.assertRaises(SystemExit):runpy.run_path(str(ASSETS/'subs.py'),run_name='__main__')
        self.assertFalse(json.loads(output.getvalue())['ok'])

    def test_exact_api_hit_is_validated_and_old_cache_is_ignored(self):
        class Response:
            def __init__(self,value):self.value=value
            def __enter__(self):return self
            def __exit__(self,*args):pass
            def read(self):return json.dumps(self.value).encode()
        calls=[]
        def api(request,**kwargs):
            calls.append(request.full_url)
            if '/get?' in request.full_url:
                item=self.item();item['artistName']='Wrong artist';return Response(item)
            return Response([self.item()])
        with tempfile.TemporaryDirectory() as tmp,patch.dict(os.environ,HOME=tmp):
            import hashlib
            cache=Path(tmp)/'.cache/quickshell/lyrics';cache.mkdir(parents=True)
            old=hashlib.sha1(b'test artist|my song').hexdigest()+'.json'
            (cache/old).write_text(json.dumps({'ok':True,'lines':[[0,'poisoned old result']]}))
            output=io.StringIO()
            with patch.object(sys,'argv',['lyrics.py','key','Test Artist','My Song','60']),patch('urllib.request.urlopen',side_effect=api),redirect_stdout(output):
                with self.assertRaises(SystemExit):runpy.run_path(str(ASSETS/'lyrics.py'),run_name='__main__')
            result=json.loads(output.getvalue());self.assertEqual(result['artist'],'Test Artist')
            self.assertEqual(result['lines'],[[1,'hello']]);self.assertEqual(len(calls),2)

    def test_actual_video_url_is_used_without_a_title_search(self):
        from types import SimpleNamespace
        calls=[]
        def yt_dlp(args,**kwargs):
            calls.append(args)
            if "--help" in args:return SimpleNamespace(returncode=0,stdout="stub",stderr="")
            self.assertIn("-J",args)
            self.assertEqual(args[-1],"https://www.youtube.com/watch?v=abcdefghijk")
            data={"events":[{"tStartMs":1000,"segs":[{"utf8":"correct video"}]}]}
            info={"subtitles":{"en":[{"ext":"json3","_data":data}]}}
            return SimpleNamespace(returncode=0,stdout=json.dumps(info),stderr="")
        with tempfile.TemporaryDirectory() as tmp,patch.dict(os.environ,HOME=tmp):
            output=io.StringIO()
            args=["subs.py","key","Same title","Channel","60","https://youtu.be/abcdefghijk"]
            with patch.object(sys,"argv",args),patch("shutil.which",return_value="stub"),patch("subprocess.run",side_effect=yt_dlp),redirect_stdout(output):
                with self.assertRaises(SystemExit):runpy.run_path(str(ASSETS/"subs.py"),run_name="__main__")
            result=json.loads(output.getvalue())
            self.assertEqual(result["id"],"abcdefghijk")
            self.assertEqual(result["lines"],[[1,"correct video"]])
            self.assertFalse(any(arg.startswith("ytsearch") for call in calls for arg in call))

    def test_player_helper_passes_url_and_clears_it_without_a_player(self):
        with tempfile.TemporaryDirectory() as tmp:
            bin=Path(tmp)/'bin';bin.mkdir();stub=bin/'playerctl'
            stub.write_text('#!'+sys.executable+'\nimport sys,os\na=sys.argv\nif "--list-all" in a:\n print("firefox" if os.environ.get("TEST_PLAYER") else "");sys.exit()\nif "status" in a:print("Playing")\nelif "position" in a:print("1")\nelif "metadata" in a:\n print({"title":"Same title","artist":"Channel","xesam:url":"https://youtube.com/watch?v=abcdefghijk","mpris:length":"60000000"}.get(a[-1],""))\n')
            stub.chmod(0o700)
            env=dict(os.environ,HOME=tmp,PATH=str(bin)+':'+os.environ['PATH'],TEST_PLAYER='yes')
            result=subprocess.check_output(['bash',str(ASSETS/'get-player.sh')],env=env,text=True)
            self.assertIn('url:https://youtube.com/watch?v=abcdefghijk\n',result)
            del env['TEST_PLAYER']
            result=subprocess.check_output(['bash',str(ASSETS/'get-player.sh')],env=env,text=True)
            self.assertIn('url:\n',result)

if __name__=='__main__':unittest.main()
