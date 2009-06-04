//  derived from http://andylangton.co.uk/jquery-show-hide
$(document).ready(function() {
  var showText='Show';
  var hideText='Hide';
  $('.toggle').prev().append('<a href="#" class="toggleLink">'+showText+'</a>');
  $('.toggle').hide();

  // capture clicks on the toggle links
  $('a.toggleLink').click(function() {
    $(this).html ($(this).html()==hideText ? showText : hideText);
    $(this).parent().next('.toggle').toggle('slow');
   // return false so any link destination is not followed
    return false;
  });
});
