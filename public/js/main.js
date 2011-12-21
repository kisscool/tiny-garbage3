var mutex = 0;

$(document).ready(function(){
  
  $("a#collapseButton").click(function(){
    if( mutex != 0  ) {
    return false;
    }
    
    if( $("#advancedSearch").is(":hidden") ) {
      $("a#collapseButton").text("Hide advanced");
      $("#collapseImg").attr("class", "collapseImgHidden");

    } else {
      $("a#collapseButton").text("Show advanced");
      $("#collapseImg").attr("class", "collapseImgVisible");
    }
    mutex = 1;
    $("#advancedSearch").toggle("slow", function() {
        mutex = 0;
    });
    return false;  
  });
});