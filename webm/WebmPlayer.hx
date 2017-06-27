package webm;
import haxe.io.Bytes;
import haxe.io.BytesData;
import flash.display.Bitmap;
import flash.display.BitmapData;
import flash.display.PixelSnapping;
import flash.display.Sprite;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.SampleDataEvent;
import flash.media.Sound;
import flash.utils.ByteArray;
import flash.utils.Endian;
import webm.internal.WebmUtils;
import lime.system.CFFI;

class WebmPlayer extends EventDispatcher {
	var webm:Webm;
	var io:WebmIo;
	var targetSprite:Sprite;
	var bitmap:Bitmap;
	var bitmapData:BitmapData;
	var decoder:Dynamic;
	var startTime:Float = 0;
	var lastDecodedVideoFrame:Float = 0;
	var playing:Bool = false;
	var renderedCount:Int = 0;
	
	public var width:Int;
	public var height:Int;
	public var frameRate:Float;
	public var duration:Float;
	
	var sound:Sound;
	var sound_enabled:Bool = false;

	public function new(io:WebmIo, targetSprite:Sprite, ?noSound:Bool = false) {
		super();
		this.io = io;
		this.targetSprite = targetSprite;
		this.webm = new Webm();
		this.decoder = hx_webm_decoder_create(io.io, noSound);
		var info = hx_webm_decoder_get_info(this.decoder);
		this.width = info[0];
		this.height = info[1];
		this.frameRate = info[2];
		this.duration = info[3];
		this.bitmapData = new BitmapData(this.width, this.height);
		this.bitmap = new Bitmap(this.bitmapData, PixelSnapping.AUTO, true);
		targetSprite.addChild(this.bitmap);

		this.sound_enabled = !noSound;

		if(sound_enabled) {
			this.outputSound = new ByteArray();
			this.outputSound.endian = Endian.LITTLE_ENDIAN;
		}
	}
	
	public var amp_multiplier_right:Float = 0.5;
	public var amp_multiplier_left:Float = 0.5;
	//public var freq_right:Float = 580;
	//public var freq_left:Float = 580;

	inline public static var SAMPLING_RATE:Int = 44100;
	//inline public static var TWO_PI:Float = 2*Math.PI;
	//inline public static var TWO_PI_OVER_SR:Float = TWO_PI/SAMPLING_RATE;
	var outputSound:ByteArray;
	
	public function generateSound(e:SampleDataEvent):Void {

		var samplel:Float;
		var sampler:Float;
		
		for (i in 0 ... 8192) {
			//samplel = Math.sin((i + e.position) * TWO_PI_OVER_SR * freq_left);
			//sampler = Math.sin((i + e.position) * TWO_PI_OVER_SR * freq_right);
			if (this.outputSound.bytesAvailable >= 8) {
				samplel = this.outputSound.readFloat();
				sampler = this.outputSound.readFloat();
				//trace(samplel + " : " + sampler);
				//trace(this.outputSound.bytesAvailable);
			} else {
				samplel = sampler = 0;
			}

			e.data.writeFloat(samplel * amp_multiplier_left);
			e.data.writeFloat(sampler * amp_multiplier_right);
		}
		
		this.outputSound.clear();
	}
	
	public function getElapsedTime():Float {
		return haxe.Timer.stamp() - this.startTime;
	}

	public function restart() {
		stop(true);
		renderedCount = 0;
		lastDecodedVideoFrame = 0;
		hx_webm_decoder_restart(decoder);
		this.dispatchEvent(new Event('restart'));
		play();
	}
	
	public function play() {
		if (!playing) {
			this.startTime = haxe.Timer.stamp();

			this.targetSprite.addEventListener("enterFrame", onSpriteEnterFrame);
			if(sound_enabled) {
				this.sound = new Sound();
				this.sound.addEventListener(SampleDataEvent.SAMPLE_DATA, generateSound);
				this.sound.play();
			}
			playing = true;
			this.dispatchEvent(new Event('play'));
		}
	}

	public function stop(?pRestart:Bool = false) {
		if (playing) {
			this.targetSprite.removeEventListener("enterFrame", onSpriteEnterFrame);
			if(sound_enabled) {
				this.sound.removeEventListener(SampleDataEvent.SAMPLE_DATA, generateSound);
				this.sound.close();
			}
			playing = false;
			if(!pRestart) this.dispatchEvent(new Event('stop'));
		}
	}
	
	private function onSpriteEnterFrame(e:Event) {
		var startRenderedCount = renderedCount;

		while (hx_webm_decoder_has_more(decoder) && lastDecodedVideoFrame < getElapsedTime()) {
		//while (hx_webm_decoder_has_more(decoder)) {
			hx_webm_decoder_step(decoder, decodeVideoFrame, outputAudioFrame);
			//if (renderedCount > startRenderedCount) break;
		}
		
		if (!hx_webm_decoder_has_more(decoder)) {
			this.dispatchEvent(new Event('end'));
			stop();
		}
	}

	private function decodeVideoFrame(time:Float, data:BytesData):Void {
		lastDecodedVideoFrame = time;
		renderedCount++;
		
		//trace("DECODE VIDEO FRAME! " + getElapsedTime() + ":" + time);
		var decodeTime:Float = WebmUtils.measureTime(function() {
			webm.decode(ByteArray.fromBytes(Bytes.ofData(data)));
		});
		var renderTime:Float = WebmUtils.measureTime(function() {
			webm.getAndRenderFrame(this.bitmapData);
		});
		
		//trace("Profiling Times: decode=" + decodeTime + " ; render=" + renderTime);
	}
	
	private function outputAudioFrame(time:Float, data:BytesData):Void {
		if(!sound_enabled) return;
		var byteArray:ByteArray = ByteArray.fromBytes(Bytes.ofData(data));
		this.outputSound.position = this.outputSound.length;
		this.outputSound.writeBytes(byteArray, 0, byteArray.length);
		this.outputSound.position = 0;
		//trace("DECODE AUDIO FRAME! " + getElapsedTime() + ":" + time);
	}
	
	static var hx_webm_decoder_create = CFFI.load("openfl-webm", "hx_webm_decoder_create", 2);
	static var hx_webm_decoder_get_info = CFFI.load("openfl-webm", "hx_webm_decoder_get_info", 1);
	static var hx_webm_decoder_has_more = CFFI.load("openfl-webm", "hx_webm_decoder_has_more", 1);
	static var hx_webm_decoder_step = CFFI.load("openfl-webm", "hx_webm_decoder_step", 3);
	static var hx_webm_decoder_restart = CFFI.load("openfl-webm", "hx_webm_decoder_restart", 1);
}