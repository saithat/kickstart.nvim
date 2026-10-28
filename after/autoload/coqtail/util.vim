" Keep the original handler for all other Coqtail warnings.
if !exists('g:CoqtailOriginalWarn')
  let g:CoqtailOriginalWarn = funcref('coqtail#util#warn')
endif

function! coqtail#util#warn(msg) abort
  if a:msg ==# "Coqtail does not officially support your version of Rocq (9.3.0).\nContinuing with the interface for the latest supported version (9.2.0)."
    return
  endif
  call g:CoqtailOriginalWarn(a:msg)
endfunction
