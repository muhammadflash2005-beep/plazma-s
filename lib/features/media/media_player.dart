// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

Future<void> showAudioPlayer(BuildContext context,{required File file,required String title}) async {
  await showModalBottomSheet<void>(context:context,useRootNavigator:true,isScrollControlled:true,
    backgroundColor:Theme.of(context).colorScheme.surface,builder:(_)=>_AudioPlayerSheet(file:file,title:title));
}
class MediaGalleryViewer extends StatefulWidget {
  const MediaGalleryViewer({required this.files,required this.isVideo,required this.initialIndex,
    required this.selectedPaths,required this.onToggleSelection,super.key});
  final List<File> files; final bool isVideo; final int initialIndex;
  final Set<String> selectedPaths; final ValueChanged<File> onToggleSelection;
  @override State<MediaGalleryViewer> createState()=>_MediaGalleryViewerState();
}
class _MediaGalleryViewerState extends State<MediaGalleryViewer> {
  late final PageController _pages; late final Player _player; late final VideoController _video;
  late final Set<String> _selected; late int _index;
  @override void initState(){super.initState();_index=widget.initialIndex.clamp(0,widget.files.length-1);
    _pages=PageController(initialPage:_index);_player=Player();_video=VideoController(_player);
    _selected={...widget.selectedPaths};if(widget.isVideo)unawaited(_openVideo(_index));}
  Future<void> _openVideo(int i) async {if(!widget.isVideo||i<0||i>=widget.files.length)return;
    try{await _player.open(Media(widget.files[i].path));}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('This video could not be played.')));}}
  void _toggle(){final f=widget.files[_index];setState(()=>_selected.contains(f.path)?_selected.remove(f.path):_selected.add(f.path));widget.onToggleSelection(f);}
  @override void dispose(){_pages.dispose();unawaited(_player.dispose());super.dispose();}
  @override Widget build(BuildContext context){final f=widget.files[_index];final selected=_selected.contains(f.path);
    return Scaffold(backgroundColor:Colors.black,appBar:AppBar(backgroundColor:Colors.black,foregroundColor:Colors.white,
      title:Text('${_index+1} of ${widget.files.length}',style:const TextStyle(fontSize:15)),
      actions:[TextButton.icon(onPressed:_toggle,icon:Icon(selected?Icons.check_circle:Icons.check_circle_outline),
        label:Text(selected?'Selected':'Select'),style:TextButton.styleFrom(foregroundColor:Colors.white)),const SizedBox(width:8)]),
      body:PageView.builder(controller:_pages,itemCount:widget.files.length,onPageChanged:(i){setState(()=>_index=i);if(widget.isVideo)unawaited(_openVideo(i));},
        itemBuilder:(context,i)=>widget.isVideo?(i==_index?Center(child:Video(controller:_video)):const ColoredBox(color:Colors.black)):
          Center(child:InteractiveViewer(minScale:.7,maxScale:5,child:Image.file(widget.files[i],fit:BoxFit.contain,
            errorBuilder:(_,__,___)=>const Icon(Icons.broken_image_outlined,color:Colors.white70,size:64))))),
      bottomNavigationBar:SafeArea(child:Container(color:Colors.black,padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
        child:Row(children:[
          IconButton(color:Colors.white,onPressed:_index==0?null:()=>_pages.previousPage(duration:const Duration(milliseconds:220),curve:Curves.easeOut),icon:const Icon(Icons.chevron_left_rounded)),
          Expanded(child:Text(f.uri.pathSegments.isEmpty?'Media':f.uri.pathSegments.last,maxLines:1,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white70,fontSize:12))),
          IconButton(color:Colors.white,onPressed:_index>=widget.files.length-1?null:()=>_pages.nextPage(duration:const Duration(milliseconds:220),curve:Curves.easeOut),icon:const Icon(Icons.chevron_right_rounded)),
        ]))));
  }
}
class _AudioPlayerSheet extends StatefulWidget {const _AudioPlayerSheet({required this.file,required this.title});final File file;final String title;
  @override State<_AudioPlayerSheet> createState()=>_AudioPlayerSheetState();}
class _AudioPlayerSheetState extends State<_AudioPlayerSheet>{late final Player _player;
  @override void initState(){super.initState();_player=Player();unawaited(_player.open(Media(widget.file.path)));}
  @override void dispose(){unawaited(_player.dispose());super.dispose();}
  String _time(Duration d){final m=d.inMinutes.remainder(60).toString().padLeft(2,'0');final s=d.inSeconds.remainder(60).toString().padLeft(2,'0');return d.inHours>0?'${d.inHours}:$m:$s':'$m:$s';}
  @override Widget build(BuildContext context){final c=Theme.of(context).colorScheme;
    return SafeArea(child:Padding(padding:EdgeInsets.fromLTRB(20,16,20,24+MediaQuery.viewInsetsOf(context).bottom),
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        Container(width:42,height:4,decoration:BoxDecoration(color:c.onSurfaceVariant.withValues(alpha:.35),borderRadius:BorderRadius.circular(4))),
        const SizedBox(height:18),CircleAvatar(radius:34,backgroundColor:c.primaryContainer,child:Icon(Icons.music_note_rounded,size:34,color:c.primary)),
        const SizedBox(height:12),Text(widget.title,textAlign:TextAlign.center,maxLines:2,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),
        const SizedBox(height:18),const _LightningBeatIndicator(),
        const SizedBox(height:12),StreamBuilder<Duration>(stream:_player.stream.duration,builder:(context,ds){final d=ds.data??Duration.zero;
          return StreamBuilder<Duration>(stream:_player.stream.position,builder:(context,ps){final p=ps.data??Duration.zero;final max=d.inMilliseconds.toDouble().clamp(1,double.infinity).toDouble();
            return Column(children:[Slider(value:p.inMilliseconds.toDouble().clamp(0,max).toDouble(),max:max,onChanged:d==Duration.zero?null:(v)=>_player.seek(Duration(milliseconds:v.round()))),
              Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(_time(p)),Text(_time(d))])]);});}),
        const SizedBox(height:6),StreamBuilder<bool>(stream:_player.stream.playing,builder:(context,s){final playing=s.data??false;
          return IconButton.filled(onPressed:()=>playing?_player.pause():_player.play(),iconSize:32,icon:Icon(playing?Icons.pause_rounded:Icons.play_arrow_rounded));}),
      ])));
  }
}

class _LightningBeatIndicator extends StatefulWidget {
  const _LightningBeatIndicator();
  @override State<_LightningBeatIndicator> createState() => _LightningBeatIndicatorState();
}
class _LightningBeatIndicatorState extends State<_LightningBeatIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  @override void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 820))..repeat();
  }
  @override void dispose() { _controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 54, width: 236,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _LightningBeatPainter(
            phase: _controller.value,
            primary: colors.primary,
            secondary: colors.secondary,
            glow: colors.primary.withValues(alpha: .38),
          ),
        ),
      ),
    );
  }
}
class _LightningBeatPainter extends CustomPainter {
  _LightningBeatPainter({required this.phase, required this.primary, required this.secondary, required this.glow});
  final double phase;
  final Color primary, secondary, glow;
  @override void paint(Canvas canvas, Size size) {
    final center = size.height / 2;
    final path = Path();
    const segments = 72;
    for (var i = 0; i <= segments; i++) {
      final x = size.width * i / segments;
      final pulse = (1 - (i / segments - phase).abs() * 1.65).clamp(0.0, 1.0);
      final beat = (i % 9 == 0 || i % 13 == 0) ? 1.0 : .28;
      final jag = (((i * 17) % 11) - 5) / 5;
      final y = center + jag * (5 + pulse * 15) * beat * (0.55 + pulse);
      if (i == 0) { path.moveTo(x, y); } else { path.lineTo(x, y); }
    }
    final glowPaint = Paint()..color = glow..style = PaintingStyle.stroke..strokeWidth = 9..strokeCap = StrokeCap.round..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    final linePaint = Paint()..shader = LinearGradient(colors:[secondary,primary,secondary]).createShader(Offset.zero & size)..style = PaintingStyle.stroke..strokeWidth = 2.6..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    final corePaint = Paint()..color = Colors.white.withValues(alpha:.9)..style = PaintingStyle.stroke..strokeWidth = .8..strokeCap = StrokeCap.round;
    canvas.drawPath(path,glowPaint); canvas.drawPath(path,linePaint); canvas.drawPath(path,corePaint);
    final sparkPaint = Paint()..color = secondary..strokeWidth = 1.4..strokeCap = StrokeCap.round;
    for (var i=0;i<5;i++) {
      final x = size.width * ((phase + i*.21) % 1);
      final h = 3 + (i%3)*2;
      canvas.drawLine(Offset(x,center-h),Offset(x+3,center+h),sparkPaint);
    }
  }
  @override bool shouldRepaint(covariant _LightningBeatPainter old) =>
      old.phase != phase || old.primary != primary || old.secondary != secondary;
}
